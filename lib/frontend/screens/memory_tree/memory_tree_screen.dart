import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../services/share_card_service.dart';
import '../../state/diary_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/saanjh_empty_state.dart';
import '../../widgets/saanjh_stagger.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

// Season from month number.
enum _Season { spring, summer, autumn, winter }

_Season _seasonFor(int month) {
  if (month >= 3 && month <= 5) return _Season.spring;
  if (month >= 6 && month <= 8) return _Season.summer;
  if (month >= 9 && month <= 11) return _Season.autumn;
  return _Season.winter;
}

// Health 0.0–1.0 for a single diary, based on DiaryWeather.
double _diaryHealth(String? diaryId) {
  if (diaryId == null) return 0.8;
  final ds = DiaryStore.instance;
  return switch (ds.weatherState(diaryId)) {
    DiaryWeather.sunny       => 1.0,
    DiaryWeather.clearingUp  => 0.7,
    DiaryWeather.partlyCloudy => 0.7,
    DiaryWeather.overcast    => 0.3,
    DiaryWeather.quiet       => 0.1,
  };
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class MemoryTreeScreen extends StatefulWidget {
  final bool isEmbedded;
  final String? diaryId; // when set: shows only this diary's tree

  const MemoryTreeScreen({
    super.key,
    this.isEmbedded = false,
    this.diaryId,
  });

  @override
  State<MemoryTreeScreen> createState() => _MemoryTreeScreenState();
}

class _MemoryTreeScreenState extends State<MemoryTreeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _breatheCtrl;
  late final AnimationController _treeRevealCtrl;
  late final AnimationController _resetCtrl;
  late final TransformationController _transformCtrl;
  _MType? _filter;
  bool _sharing = false;
  bool _isTransformed = false; // true when user has zoomed/panned

  // Key for the off-screen _TreeShareCard rendered in Offstage.
  final _treeShareCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _treeRevealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _resetCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
    );
    _transformCtrl = TransformationController();
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _treeRevealCtrl.dispose();
    _resetCtrl.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  void _resetView() {
    if (!_isTransformed) return;
    _resetCtrl.reset();
    final begin = _transformCtrl.value.clone();
    final anim = Matrix4Tween(begin: begin, end: Matrix4.identity())
        .animate(CurvedAnimation(parent: _resetCtrl, curve: AppMotion.easeOut));
    anim.addListener(() => _transformCtrl.value = anim.value);
    _resetCtrl.forward().whenComplete(() {
      if (mounted) setState(() => _isTransformed = false);
    });
  }

  String? get _contactName {
    if (widget.diaryId == null) return null;
    try {
      return DiaryStore.instance.diaries
          .firstWhere((d) => d.id == widget.diaryId)
          .displayName;
    } catch (_) {
      return null;
    }
  }

  // ── Weather ───────────────────────────────────────────────────────────────

  DiaryWeather _treeWeather() {
    final ds = DiaryStore.instance;
    if (widget.diaryId != null) return ds.weatherState(widget.diaryId!);
    if (ds.diaries.isEmpty) return DiaryWeather.overcast;
    // For combined view: show the best (most positive) weather across diaries.
    DiaryWeather best = DiaryWeather.quiet;
    for (final d in ds.diaries) {
      final w = ds.weatherState(d.id);
      if (w == DiaryWeather.sunny) return DiaryWeather.sunny;
      if (w == DiaryWeather.clearingUp) {
        best = DiaryWeather.clearingUp;
      } else if (w == DiaryWeather.partlyCloudy &&
          best != DiaryWeather.clearingUp) {
        best = DiaryWeather.partlyCloudy;
      } else if (w == DiaryWeather.overcast &&
          best == DiaryWeather.quiet) {
        best = DiaryWeather.overcast;
      }
    }
    return best;
  }

  String _weatherLabel(DiaryWeather w) => switch (w) {
        DiaryWeather.sunny        => '☀ SUNNY',
        DiaryWeather.clearingUp   => '🌤 CLEARING UP',
        DiaryWeather.partlyCloudy => '⛅ PARTLY CLOUDY',
        DiaryWeather.overcast     => '🌥 OVERCAST',
        DiaryWeather.quiet        => '🌧 QUIET LATELY',
      };

  // ── Share ─────────────────────────────────────────────────────────────────

  ({int totalMoments, int yearsCount}) _treeStats() {
    final ds = DiaryStore.instance;
    final diaries = widget.diaryId != null
        ? ds.diaries.where((d) => d.id == widget.diaryId).toList()
        : ds.diaries;
    int total = 0;
    final years = <int>{};
    for (final d in diaries) {
      for (final e in ds.entriesFor(d.id)) {
        total++;
        years.add(e.createdAt.year);
      }
    }
    return (totalMoments: total, yearsCount: years.length);
  }

  int _monthCount() {
    final ds = DiaryStore.instance;
    if (widget.diaryId != null) {
      return ds.momentsByMonth(widget.diaryId!).keys.length;
    }
    final merged = <String>{};
    for (final d in ds.diaries) {
      merged.addAll(ds.momentsByMonth(d.id).keys);
    }
    return merged.length;
  }

  String _seasonLabel(_Season season) => switch (season) {
        _Season.spring => 'Spring',
        _Season.summer => 'Summer',
        _Season.autumn => 'Autumn',
        _Season.winter => 'Winter',
      };

  Future<void> _shareTree(_Season season) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final stats = _treeStats();
      await ShareCardService.instance.shareTreeCard(
        _treeShareCardKey,
        seasonLabel: _seasonLabel(season),
        totalMoments: stats.totalMoments,
        yearsCount: stats.yearsCount,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  bool get _isEmpty {
    if (widget.diaryId != null) {
      return DiaryStore.instance.entriesFor(widget.diaryId!).isEmpty;
    }
    return DiaryStore.instance.diaries
        .every((d) => DiaryStore.instance.entriesFor(d.id).isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final treeH = MediaQuery.of(context).size.width * 0.84;
    final health = _diaryHealth(widget.diaryId);
    final season = _seasonFor(DateTime.now().month);
    final isEmpty = _isEmpty;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.inkRaised, AppColors.ink, AppColors.inkDeep],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Header ────────────────────────────────────────────────────
              SliverSafeArea(
                bottom: false,
                sliver: SliverToBoxAdapter(
                  child: _Header(
                    isEmbedded: widget.isEmbedded,
                    contactName: _contactName,
                    canShare: !isEmpty,
                    sharing: _sharing,
                    onShare: isEmpty ? null : () => _shareTree(season),
                    weatherLabel: isEmpty
                        ? null
                        : _weatherLabel(_treeWeather()),
                  ),
                ),
              ),

              // ── Tree canvas — pinch-to-zoom via InteractiveViewer ─────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: treeH,
                  child: isEmpty
                      ? _EmptySeed(
                          ctrl: _breatheCtrl,
                          diaryId: widget.diaryId,
                        )
                      : InteractiveViewer(
                          transformationController: _transformCtrl,
                          minScale: 0.8,
                          maxScale: 2.4,
                          constrained: false,
                          onInteractionUpdate: (_) {
                            if (!_isTransformed) {
                              setState(() => _isTransformed = true);
                            }
                          },
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width,
                            height: treeH,
                            child: _TreeCanvas(
                              ctrl: _breatheCtrl,
                              revealCtrl: _treeRevealCtrl,
                              season: season,
                              health: health,
                              diaryId: widget.diaryId,
                              filter: _filter,
                            ),
                          ),
                        ),
                ),
              ),

              // ── Reset view button — appears when zoomed/panned ────────────
              if (_isTransformed)
                SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: GestureDetector(
                        onTap: _resetView,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.center_focus_strong_rounded,
                                  size: 13,
                                  color: AppColors.textFaint),
                              const SizedBox(width: 6),
                              Text('Reset view',
                                  style: AppTypography.caption(
                                      color: AppColors.textFaint)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Filter row ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _FilterRow(
                  selected: _filter,
                  onSelect: (t) =>
                      setState(() => _filter = _filter == t ? null : t),
                ),
              ),

              // ── Stats card ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _StatsCard(diaryId: widget.diaryId),
                ),
              ),

              // ── Memory Book CTA ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _BookBanner(
                    onTap: () => context.push(AppRoutes.memoryBook),
                    onShareTree: isEmpty ? null : () => _shareTree(season),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 28),
              ),
            ],
          ),

          // ── Off-screen share card ────────────────────────────────────────
          Offstage(
            child: _TreeShareCard(
              key: _treeShareCardKey,
              season: season,
              health: health,
              monthCount: _monthCount(),
              stats: _treeStats(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final bool isEmbedded;
  final String? contactName;
  final bool canShare;
  final bool sharing;
  final VoidCallback? onShare;
  // Nullable: only shown when tree has content.
  final String? weatherLabel;

  const _Header({
    required this.isEmbedded,
    this.contactName,
    this.canShare = false,
    this.sharing = false,
    this.onShare,
    this.weatherLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
      child: Row(
        children: [
          if (!isEmbedded) ...[
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                context.pop();
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08), width: 1),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 14, color: Color(0x9EF5EFE8)),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show weather state when tree has content; else 'MOMENTS'
              Text(
                weatherLabel ?? 'MOMENTS',
                style: AppTypography.eyebrow(
                  size: 10,
                  color: weatherLabel != null
                      ? AppColors.emberBright.withValues(alpha: 0.80)
                      : AppColors.emberBright,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                contactName != null
                    ? "$contactName's Memory Tree"
                    : 'Memory Tree',
                style: AppTypography.title(size: 24),
              ),
            ],
          ),

          const Spacer(),

          // Share icon — only shown when tree has content
          if (canShare)
            GestureDetector(
              onTap: sharing ? null : onShare,
              child: AnimatedOpacity(
                opacity: sharing ? 0.40 : 1.0,
                duration: AppMotion.fast,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08), width: 1),
                  ),
                  child: sharing
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.emberWarm,
                          ),
                        )
                      : const Icon(Icons.ios_share_rounded,
                          size: 16, color: AppColors.emberWarm),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Empty seed ───────────────────────────────────────────────────────────────

class _EmptySeed extends StatelessWidget {
  final AnimationController ctrl;
  final String? diaryId;
  const _EmptySeed({required this.ctrl, this.diaryId});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, _) {
        final scale = 1.0 + 0.30 * ctrl.value;
        return SaanjhEmptyState(
          visual: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (diaryId != null) {
                context.push(AppRoutes.diaryThread,
                    extra: {'diaryId': diaryId});
              } else {
                context.push(AppRoutes.voiceRecord,
                    extra: {'isVideo': false});
              }
            },
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.ember,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ember.withValues(alpha: 0.5 * ctrl.value),
                      blurRadius: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          title: 'Plant the first memory.',
          body: null,
          ctaLabel: 'Start a diary →',
          onCta: () {
            HapticFeedback.lightImpact();
            context.push(AppRoutes.discover);
          },
        );
      },
    );
  }
}

// ─── Tree canvas (interactive) ────────────────────────────────────────────────

enum _MType { voice, video, photo }

class _TreeCanvas extends StatefulWidget {
  final AnimationController ctrl;
  final AnimationController revealCtrl;
  final _Season season;
  final double health;
  final String? diaryId;
  final _MType? filter;

  const _TreeCanvas({
    required this.ctrl,
    required this.revealCtrl,
    required this.season,
    required this.health,
    this.diaryId,
    this.filter,
  });

  @override
  State<_TreeCanvas> createState() => _TreeCanvasState();
}

class _TreeCanvasState extends State<_TreeCanvas>
    with SingleTickerProviderStateMixin {
  // Sorted months with entries: ['YYYY-MM', ...] newest first
  List<String> _monthKeys = [];
  // Node indices (0-based) for months that have at least one entry with reactions.
  Set<int> _reactionNodeIndices = {};
  // Average moodEnergy per month (parallel to _monthKeys). 0.5 = neutral/unknown.
  List<double> _monthMoodEnergies = [];

  // Ripple animation — plays when a new reaction arrives on a node.
  late final AnimationController _rippleCtrl;
  int? _rippleNodeIdx;

  @override
  void initState() {
    super.initState();
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _updateMonthKeys();
    DiaryStore.instance.addListener(_onStoreChange);
  }

  @override
  void didUpdateWidget(_TreeCanvas old) {
    super.didUpdateWidget(old);
    // Re-compute if the target diary changes (e.g. navigating between contacts).
    if (old.diaryId != widget.diaryId) {
      _updateMonthKeys();
    }
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    DiaryStore.instance.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    final prevIndices = Set<int>.from(_reactionNodeIndices);
    setState(_updateMonthKeys);
    // Detect newly-reacted nodes and trigger ripple.
    final newIndices = _reactionNodeIndices.difference(prevIndices);
    if (newIndices.isNotEmpty) {
      _rippleNodeIdx = newIndices.first;
      _rippleCtrl.forward(from: 0);
    }
  }

  void _updateMonthKeys() {
    final Map<String, List<String>> byMonth;
    if (widget.diaryId != null) {
      byMonth = DiaryStore.instance.momentsByMonth(widget.diaryId!);
    } else {
      // Merge all diaries
      final merged = <String, List<String>>{};
      for (final d in DiaryStore.instance.diaries) {
        DiaryStore.instance.momentsByMonth(d.id).forEach((k, v) {
          merged.putIfAbsent(k, () => []).addAll(v);
        });
      }
      byMonth = merged;
    }
    final keys = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    _monthKeys = keys;

    // Compute which node indices have reactions.
    final newReactionIndices = <int>{};
    final diaries = widget.diaryId != null
        ? DiaryStore.instance.diaries
            .where((d) => d.id == widget.diaryId)
        : DiaryStore.instance.diaries;
    for (int i = 0; i < keys.length; i++) {
      final key = keys[i];
      outer:
      for (final diary in diaries) {
        for (final entry in DiaryStore.instance.entriesFor(diary.id)) {
          final entryKey =
              '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}';
          if (entryKey == key && entry.reactions.isNotEmpty) {
            newReactionIndices.add(i);
            break outer;
          }
        }
      }
    }
    _reactionNodeIndices = newReactionIndices;

    // Compute average moodEnergy per month for node colour variation.
    _monthMoodEnergies = keys.map((key) {
      final energies = <double>[];
      for (final diary in diaries) {
        for (final entry in DiaryStore.instance.entriesFor(diary.id)) {
          final entryKey =
              '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}';
          if (entryKey == key && entry.moodEnergy != null) {
            energies.add(entry.moodEnergy!);
          }
        }
      }
      return energies.isEmpty
          ? 0.5 // neutral — no data yet
          : energies.reduce((a, b) => a + b) / energies.length;
    }).toList();
  }

  // Compute hit rects from the node positions used by _TreePainter.
  // Mirrors the ring-1 + ring-2 layout in _drawNodes() exactly.
  List<({Rect rect, int index})> _computeHits(Size size) {
    final cx = size.width / 2;
    final base = size.height * 0.92;
    final h = size.height;
    final w = size.width;

    // Ring 1 — 9 fixed branch-tip positions (radius 32 hit area)
    final ring1 = [
      Offset(cx,            base - h * 0.40),
      Offset(cx - w * 0.22, base - h * 0.67),
      Offset(cx + w * 0.22, base - h * 0.67),
      Offset(cx - w * 0.30, base - h * 0.57),
      Offset(cx + w * 0.30, base - h * 0.57),
      Offset(cx - w * 0.36, base - h * 0.90),
      Offset(cx - w * 0.14, base - h * 0.90),
      Offset(cx + w * 0.14, base - h * 0.90),
      Offset(cx + w * 0.36, base - h * 0.90),
    ];

    // Ring 2 — 15 golden-angle spiral nodes (radius 24 hit area, smaller nodes)
    const goldenAngle = 2.3998631;
    final treeCy = base - h * 0.62;
    final ring2 = <Offset>[];
    for (int ri = 0; ri < 15; ri++) {
      final r = (0.30 + ri * 0.022) * h;
      final theta = ri * goldenAngle;
      final nx = cx + r * math.cos(theta);
      final ny = treeCy - r * math.sin(theta);
      ring2.add(Offset(nx, ny));
    }

    final hits = <({Rect rect, int index})>[];
    for (int i = 0; i < ring1.length; i++) {
      hits.add((rect: Rect.fromCircle(center: ring1[i], radius: 32), index: i));
    }
    for (int i = 0; i < ring2.length; i++) {
      hits.add((
        rect: Rect.fromCircle(center: ring2[i], radius: 24),
        index: ring1.length + i,
      ));
    }
    return hits;
  }

  void _onTapDown(TapDownDetails details, Size size) {
    final tap = details.localPosition;
    final hits = _computeHits(size);
    for (final hit in hits) {
      if (hit.rect.contains(tap)) {
        HapticFeedback.selectionClick();
        final monthKey =
            hit.index < _monthKeys.length ? _monthKeys[hit.index] : null;
        _showMonthSheet(monthKey);
        return;
      }
    }
  }

  void _showMonthSheet(String? monthKey) {
    if (monthKey == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MonthDetailSheet(
        monthKey: monthKey,
        diaryId: widget.diaryId,
        filter: widget.filter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapDown: (d) => _onTapDown(d, size),
          child: AnimatedBuilder(
            animation: Listenable.merge(
                [widget.ctrl, widget.revealCtrl, _rippleCtrl]),
            builder: (_, _) => CustomPaint(
              size: size,
              painter: _TreePainter(
                breathe: widget.ctrl.value,
                revealProgress: widget.revealCtrl.value,
                season: widget.season,
                health: widget.health,
                monthCount: _monthKeys.length,
                reactionNodeIndices: _reactionNodeIndices,
                monthMoodEnergies: _monthMoodEnergies,
                filter: widget.filter,
                rippleNodeIdx: _rippleNodeIdx,
                rippleProgress: _rippleCtrl.value,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Tree painter (seasonal + health-aware) ───────────────────────────────────

class _TreePainter extends CustomPainter {
  final double breathe;
  final double revealProgress; // 0.0→1.0: trunk(0–0.3) → branches(0.3–0.7) → leaves(0.7–1.0)
  final _Season season;
  final double health; // 0.0–1.0
  final int monthCount; // how many months have entries

  final Set<int> reactionNodeIndices;
  // Per-node average moodEnergy (0.0–1.0). 0.5 = neutral/unknown.
  final List<double> monthMoodEnergies;
  // Active filter — non-matching nodes are drawn at reduced opacity.
  final _MType? filter;
  // Ripple: which node index is currently rippling and how far (0→1).
  final int? rippleNodeIdx;
  final double rippleProgress;

  _TreePainter({
    required this.breathe,
    required this.revealProgress,
    required this.season,
    required this.health,
    required this.monthCount,
    this.reactionNodeIndices = const {},
    this.monthMoodEnergies = const [],
    this.filter,
    this.rippleNodeIdx,
    this.rippleProgress = 0.0,
  });

  // Seasonal leaf density (before health scaling)
  double get _baseDensity => switch (season) {
        _Season.spring => 0.7,
        _Season.summer => 1.0,
        _Season.autumn => 0.5,
        _Season.winter => 0.0,
      };

  double get _leafDensity => _baseDensity * health;

  Color get _leafColor => switch (season) {
        _Season.spring => const Color(0xFFB4DC78), // RGB(180, 220, 120)
        _Season.summer => const Color(0xFF3CA050), // RGB(60, 160, 80)
        _Season.autumn => const Color(0xFFDC7828), // RGB(220, 120, 40)
        _Season.winter => Colors.white,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final base = size.height * 0.92;
    final breatheScale = 1.0 + 0.015 * breathe;

    // Reveal phase guards: trunk 0–0.3, branches 0.3–0.7, leaves/nodes 0.7–1.0
    final trunkReveal = (revealProgress / 0.3).clamp(0.0, 1.0);
    final branchReveal = ((revealProgress - 0.3) / 0.4).clamp(0.0, 1.0);
    final leafReveal = ((revealProgress - 0.7) / 0.3).clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(cx, base);
    canvas.scale(breatheScale);
    canvas.translate(-cx, -base);

    if (trunkReveal > 0) _drawTrunk(canvas, cx, base, size, trunkReveal);
    if (branchReveal > 0) _drawBranches(canvas, cx, base, size, branchReveal);
    if (leafReveal > 0) {
      _drawLeaves(canvas, cx, base, size);
      if (season == _Season.winter) _drawWinterParticles(canvas, size);
      if (season == _Season.autumn) _drawFallingLeaves(canvas, size);
      _drawNodes(canvas, cx, base, size, leafReveal);
    }

    canvas.restore();
  }

  void _drawTrunk(Canvas canvas, double cx, double base, Size size,
      [double reveal = 1.0]) {
    final thickness = 2.0 + health * 2.0;
    // Trunk grows from base upward proportional to reveal (0→1).
    canvas.drawLine(
      Offset(cx, base),
      Offset(cx, base - size.height * 0.40 * reveal),
      Paint()
        ..color = AppColors.ember.withValues(alpha: 0.25 + health * 0.15)
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawBranches(Canvas canvas, double cx, double base, Size size,
      [double reveal = 1.0]) {
    final h = size.height;
    final w = size.width;
    final thickness = 1.5 + health * 1.5;

    final branches = [
      (cx, base - h * 0.40, cx - w * 0.22, base - h * 0.67),
      (cx, base - h * 0.40, cx + w * 0.22, base - h * 0.67),
      (cx, base - h * 0.30, cx - w * 0.30, base - h * 0.57),
      (cx, base - h * 0.30, cx + w * 0.30, base - h * 0.57),
      (cx - w * 0.22, base - h * 0.67, cx - w * 0.36, base - h * 0.90),
      (cx - w * 0.22, base - h * 0.67, cx - w * 0.14, base - h * 0.90),
      (cx + w * 0.22, base - h * 0.67, cx + w * 0.36, base - h * 0.90),
      (cx + w * 0.22, base - h * 0.67, cx + w * 0.14, base - h * 0.90),
    ];

    final paint = Paint()
      ..color = AppColors.ember.withValues(alpha: (0.20 + health * 0.10) * reveal)
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    for (final (x1, y1, x2, y2) in branches) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  void _drawLeaves(Canvas canvas, double cx, double base, Size size) {
    if (_leafDensity < 0.05) return;

    final h = size.height;
    final w = size.width;
    final rng = math.Random(DateTime.now().month * 100);

    // Leaf cluster positions (branch tips + mid-points)
    final clusterCentres = [
      Offset(cx,            base - h * 0.40),
      Offset(cx - w * 0.22, base - h * 0.67),
      Offset(cx + w * 0.22, base - h * 0.67),
      Offset(cx - w * 0.30, base - h * 0.57),
      Offset(cx + w * 0.30, base - h * 0.57),
      Offset(cx - w * 0.36, base - h * 0.90),
      Offset(cx + w * 0.36, base - h * 0.90),
    ];

    final leafAlpha = _leafDensity * 0.55;
    final leafPaint = Paint()
      ..color = _leafColor.withValues(alpha: leafAlpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    for (final centre in clusterCentres) {
      final count = (8 * _leafDensity).round().clamp(2, 10);
      for (int i = 0; i < count; i++) {
        final angle = rng.nextDouble() * math.pi * 2;
        final dist = 12 + rng.nextDouble() * 18;
        final pos = centre + Offset(math.cos(angle) * dist,
                                    math.sin(angle) * dist);
        final r = 4.0 + rng.nextDouble() * 5.0;
        canvas.drawCircle(pos, r, leafPaint);
      }
    }
  }

  void _drawWinterParticles(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12 + 0.08 * breathe);

    for (int i = 0; i < 18; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * 0.85;
      canvas.drawCircle(Offset(x, y), 1.5, paint);
    }
  }

  void _drawFallingLeaves(Canvas canvas, Size size) {
    final leafColor = _leafColor.withValues(alpha: 0.65);
    final paint = Paint()..color = leafColor;

    // 4 falling leaves with staggered phase
    for (int i = 0; i < 4; i++) {
      final phase = i * 0.25;
      final t = (breathe + phase) % 1.0;
      final x = size.width * (0.2 + i * 0.18) +
          math.sin((breathe + phase) * math.pi * 2) * 12;
      final y = size.height * 0.05 + t * size.height * 0.70;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((breathe + phase) * math.pi * 0.5);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 8, height: 5),
        paint,
      );
      canvas.restore();
    }
  }

  void _drawNodes(Canvas canvas, double cx, double base, Size size,
      [double reveal = 1.0]) {
    final h = size.height;
    final w = size.width;

    final nodes = [
      (cx,            base - h * 0.40, 'voice', 1.00),
      (cx - w * 0.22, base - h * 0.67, 'voice', 0.80),
      (cx + w * 0.22, base - h * 0.67, 'voice', 0.90),
      (cx - w * 0.30, base - h * 0.57, 'video', 0.65),
      (cx + w * 0.30, base - h * 0.57, 'voice', 0.80),
      (cx - w * 0.36, base - h * 0.90, 'video', 0.70),
      (cx - w * 0.14, base - h * 0.90, 'photo', 0.75),
      (cx + w * 0.14, base - h * 0.90, 'voice', 0.60),
      (cx + w * 0.36, base - h * 0.90, 'voice', 0.85),
    ];

    // Cap at 24 to prevent perf degradation for very long-lived accounts.
    final totalSlots = 24;
    final ring1Count = nodes.length; // 9

    // Golden angle (π × (3 − √5)) — produces maximally spread spiral.
    const goldenAngle = 2.3998631;
    // Centre of the tree's visual mass (roughly mid-canopy).
    final treeCy = base - h * 0.62;

    // Ring 2: nodes at indices 9–23, spiral outward from tree centre.
    final ring2 = <(double, double, String, double)>[];
    for (int ri = 0; ri < totalSlots - ring1Count; ri++) {
      final r = (0.30 + ri * 0.022) * h;
      final theta = ri * goldenAngle;
      final nx = cx + r * math.cos(theta);
      final ny = treeCy - r * math.sin(theta);
      // Keep within canvas bounds.
      if (nx < 8 || nx > size.width - 8 || ny < 8 || ny > size.height - 8) {
        ring2.add((nx, ny, 'voice', 0.0)); // invisible sentinel — correct index
        continue;
      }
      final type = ri % 5 == 2 ? 'video' : ri % 7 == 4 ? 'photo' : 'voice';
      final glow = 0.50 + (ri % 3) * 0.08;
      ring2.add((nx, ny, type, glow));
    }

    // Only show nodes up to monthCount (or all if > monthCount).
    final visibleCount = monthCount > 0
        ? math.min(totalSlots, monthCount)
        : ring1Count;

    for (int ni = 0; ni < visibleCount; ni++) {
      final (x, y, type, glow) = nodes[ni];
      final nodeGlow = glow * health;
      final color = switch (type) {
        'video' => AppColors.violet,
        'photo' => AppColors.azure,
        _       => AppColors.emberWarm,
      };

      // Dim nodes that don't match the active filter (0.18 = barely visible).
      final matchesFilter = filter == null ||
          (filter == _MType.voice && type == 'voice') ||
          (filter == _MType.video && type == 'video') ||
          (filter == _MType.photo && type == 'photo');
      final dimFactor = matchesFilter ? 1.0 : 0.18;

      canvas.drawCircle(
        Offset(x, y), 16,
        Paint()
          ..color = color.withValues(alpha: 0.30 * nodeGlow * dimFactor)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      canvas.drawCircle(
        Offset(x, y), 9,
        Paint()..color = color.withValues(alpha: nodeGlow * dimFactor),
      );
      canvas.drawCircle(
        Offset(x, y), 9,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.40 * dimFactor)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

      // Mood energy tint — subtle hue shift based on month's average energy.
      // high energy (>0.6) → warm amber overlay
      // low energy (<0.3) → cool teal overlay
      // neutral (0.3–0.6) → no overlay
      if (ni < monthMoodEnergies.length) {
        final energy = monthMoodEnergies[ni];
        if (energy > 0.6) {
          final t = ((energy - 0.6) / 0.4).clamp(0.0, 1.0);
          canvas.drawCircle(
            Offset(x, y), 9,
            Paint()
              ..color = const Color(0xFFFF9500).withValues(alpha: 0.28 * t),
          );
        } else if (energy < 0.3) {
          final t = ((0.3 - energy) / 0.3).clamp(0.0, 1.0);
          canvas.drawCircle(
            Offset(x, y), 9,
            Paint()
              ..color = const Color(0xFF5AC8FA).withValues(alpha: 0.28 * t),
          );
        }
      }

      // ✦ reaction marker — 4-pointed star, amber, 6px, top-right of node
      if (reactionNodeIndices.contains(ni)) {
        _drawStarMarker(
          canvas,
          Offset(x + 10, y - 10),
          6.0,
          AppColors.emberWarm,
        );
      }

      // ◉ ripple rings — 3 expanding circles when a new reaction arrives
      if (ni == rippleNodeIdx && rippleProgress > 0) {
        for (int ri = 0; ri < 3; ri++) {
          final delay = ri * 0.18;
          final p = ((rippleProgress - delay) / (1.0 - delay)).clamp(0.0, 1.0);
          if (p <= 0) continue;
          final radius = 9.0 + p * 38;
          final alpha = (1.0 - p) * 0.50;
          canvas.drawCircle(
            Offset(x, y),
            radius,
            Paint()
              ..color = AppColors.emberWarm.withValues(alpha: alpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }

    // ── Ring 2: extended months (9–23) ────────────────────────────────────
    for (int ri = 0; ri < ring2.length; ri++) {
      final globalIdx = ring1Count + ri;
      if (globalIdx >= visibleCount) break;
      final (nx, ny, rType, rGlow) = ring2[ri];
      if (rGlow <= 0.0) continue; // out-of-bounds sentinel

      final rColor = switch (rType) {
        'video' => AppColors.violet,
        'photo' => AppColors.azure,
        _       => AppColors.emberWarm,
      };
      final rNodeGlow = rGlow * health;
      final matchesRFilter = filter == null ||
          (filter == _MType.voice && rType == 'voice') ||
          (filter == _MType.video && rType == 'video') ||
          (filter == _MType.photo && rType == 'photo');
      final rDim = matchesRFilter ? 1.0 : 0.18;

      // Smaller node for ring 2 (radius 6, glow 10)
      canvas.drawCircle(
        Offset(nx, ny), 10,
        Paint()
          ..color = rColor.withValues(alpha: 0.22 * rNodeGlow * rDim)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        Offset(nx, ny), 6,
        Paint()..color = rColor.withValues(alpha: rNodeGlow * rDim),
      );
      canvas.drawCircle(
        Offset(nx, ny), 6,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.30 * rDim)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );

      if (reactionNodeIndices.contains(globalIdx)) {
        _drawStarMarker(canvas, Offset(nx + 7, ny - 7), 5.0, AppColors.emberWarm);
      }
    }

    // Ground glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, base), width: 160, height: 30),
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.ember.withValues(alpha: 0.12 * health),
            Colors.transparent,
          ],
        ).createShader(
            Rect.fromCircle(center: Offset(cx, base), radius: 80)),
    );
  }

  // Draws a 4-pointed star centred at [centre] with outer radius [size/2].
  void _drawStarMarker(
      Canvas canvas, Offset centre, double size, Color color) {
    final r = size / 2;
    final r2 = r * 0.35;
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final radius = i.isEven ? r : r2;
      final pt = Offset(
        centre.dx + radius * math.cos(angle),
        centre.dy + radius * math.sin(angle),
      );
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      old.breathe != breathe ||
      old.revealProgress != revealProgress ||
      old.health != health ||
      old.season != season ||
      old.monthCount != monthCount ||
      old.reactionNodeIndices != reactionNodeIndices ||
      old.monthMoodEnergies != monthMoodEnergies ||
      old.filter != filter ||
      old.rippleNodeIdx != rippleNodeIdx ||
      old.rippleProgress != rippleProgress;
}

// ─── Month detail sheet ───────────────────────────────────────────────────────

class _MonthDetailSheet extends StatefulWidget {
  final String monthKey; // 'YYYY-MM'
  final String? diaryId;
  final _MType? filter;

  const _MonthDetailSheet({
    required this.monthKey,
    this.diaryId,
    this.filter,
  });

  @override
  State<_MonthDetailSheet> createState() => _MonthDetailSheetState();
}

class _MonthDetailSheetState extends State<_MonthDetailSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveCtrl;
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  String get _monthLabel {
    final parts = widget.monthKey.split('-');
    if (parts.length < 2) return widget.monthKey;
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final m = int.tryParse(parts[1]) ?? 1;
    return '${months[m]} ${parts[0]}';
  }

  // Collect all entries for this month across the relevant diaries,
  // then apply the active filter if one is set.
  List<({DiaryEntry entry, DiaryContact diary})> _entries() {
    final ds = DiaryStore.instance;
    final diaries = widget.diaryId != null
        ? ds.diaries.where((d) => d.id == widget.diaryId).toList()
        : ds.diaries;

    final result = <({DiaryEntry entry, DiaryContact diary})>[];
    for (final diary in diaries) {
      final byMonth = ds.momentsByMonth(diary.id);
      final ids = byMonth[widget.monthKey] ?? [];
      final allEntries = ds.entriesFor(diary.id);
      for (final id in ids) {
        try {
          final entry = allEntries.firstWhere((e) => e.id == id);
          result.add((entry: entry, diary: diary));
        } catch (_) {}
      }
    }
    result.sort((a, b) => b.entry.createdAt.compareTo(a.entry.createdAt));

    if (widget.filter != null) {
      final typeStr = switch (widget.filter!) {
        _MType.voice => 'voice',
        _MType.video => 'video',
        _MType.photo => 'photo',
      };
      result.removeWhere((e) => e.entry.type != typeStr);
    }

    return result;
  }

  String get _filterEmptyMessage {
    if (widget.filter == null) return 'No moments recorded this month.';
    return switch (widget.filter!) {
      _MType.voice => 'No voice notes recorded this month.',
      _MType.video => 'No video clips recorded this month.',
      _MType.photo => 'No photos recorded this month.',
    };
  }

  String _dateLabel(DiaryEntry entry) {
    final d = entry.createdAt;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0606),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Handle
          Center(
            child: Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Month label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(_monthLabel, style: AppTypography.title(size: 20)),
                const Spacer(),
                Text(
                  '${entries.length} moment${entries.length == 1 ? '' : 's'}',
                  style: AppTypography.label(
                      size: 12, color: AppColors.textFaint),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Entries list
          Flexible(
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _filterEmptyMessage,
                      style: AppTypography.serifItalic(size: 15),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final isPlaying = _playingId == e.entry.id;
                      return _EntryRow(
                        entry: e.entry,
                        diary: e.diary,
                        dateLabel: _dateLabel(e.entry),
                        isPlaying: isPlaying,
                        waveCtrl: _waveCtrl,
                        monthLabel: _monthLabel,
                        onPlay: () => setState(() {
                          _playingId = isPlaying ? null : e.entry.id;
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatefulWidget {
  final DiaryEntry entry;
  final DiaryContact diary;
  final String dateLabel;
  final bool isPlaying;
  final AnimationController waveCtrl;
  final VoidCallback onPlay;
  final String monthLabel;

  const _EntryRow({
    required this.entry,
    required this.diary,
    required this.dateLabel,
    required this.isPlaying,
    required this.waveCtrl,
    required this.onPlay,
    required this.monthLabel,
  });

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _reactionsExpanded = false;

  void _react(BuildContext context) {
    context.push(
      AppRoutes.voiceRecord,
      extra: {
        'isVideo': false,
        'autoStart': true,
        'targetDiaryId': widget.diary.id,
        'parentEntryId': widget.entry.id,
        'reactionContext':
            'Reacting to a memory from ${widget.monthLabel}',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final reactionCount = widget.entry.reactions.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Contact avatar
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.diary.avatarColor.withValues(alpha: 0.25),
                ),
                child: Center(
                  child: Text(widget.diary.initial,
                      style: AppTypography.label(
                          size: 13, color: widget.diary.avatarColor)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.diary.displayName,
                      style: AppTypography.label(
                          size: 13, color: AppColors.text),
                    ),
                    Text(
                      '${widget.dateLabel} · ${widget.entry.type == 'video' ? 'Video' : 'Voice'}',
                      style: AppTypography.label(
                          size: 11, color: AppColors.textFaint),
                    ),
                  ],
                ),
              ),
              Text(
                widget.entry.type == 'video' ? '🎬' : '🎙',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 8),
              // Play button
              GestureDetector(
                onTap: widget.onPlay,
                child: widget.isPlaying
                    ? AnimatedBuilder(
                        animation: widget.waveCtrl,
                        builder: (_, _) =>
                            _MiniWave(ctrl: widget.waveCtrl),
                      )
                    : Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.ember.withValues(alpha: 0.18),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            size: 16, color: AppColors.emberWarm),
                      ),
              ),
            ],
          ),

          // React button
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 0, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () => _react(context),
                child: Text(
                  'React with your voice 🎙',
                  style: AppTypography.label(
                      size: 11, color: AppColors.textFaint),
                ),
              ),
              // Reactions expander
              if (reactionCount > 0) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    if (!_reactionsExpanded) HapticFeedback.lightImpact();
                    setState(() => _reactionsExpanded = !_reactionsExpanded);
                  },
                  child: Text(
                    'Reactions ($reactionCount) ${_reactionsExpanded ? '▴' : '▾'}',
                    style: AppTypography.label(
                        size: 11, color: AppColors.emberWarm),
                  ),
                ),
              ],
            ],
          ),

          // Expanded reactions — each row slides in with a stagger delay
          if (_reactionsExpanded && reactionCount > 0) ...[
            const SizedBox(height: 8),
            ...widget.entry.reactions.asMap().entries.map((e) {
              final idx = e.key;
              final r   = e.value;
              return SaanjhStaggerItem(
                key: ValueKey('reaction-${r.id}'),
                index: idx,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.ember.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.emberWarm.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text('🎙', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r.transcript ?? 'Voice reaction',
                            style: AppTypography.label(
                                size: 12, color: AppColors.textMuted),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _MiniWave extends StatelessWidget {
  final AnimationController ctrl;
  const _MiniWave({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32, height: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(4, (i) {
          final phase = math.sin((ctrl.value + i * 0.2) * math.pi * 2);
          final h = (3.0 + phase.abs() * 12).clamp(3.0, 15.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Container(
              width: 3, height: h,
              decoration: BoxDecoration(
                color: AppColors.emberWarm.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Filter row ───────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final _MType? selected;
  final ValueChanged<_MType> onSelect;

  const _FilterRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          _FilterChip(
            color: AppColors.emberWarm,
            icon: Icons.mic_rounded,
            label: 'Voice',
            active: selected == _MType.voice,
            onTap: () => onSelect(_MType.voice),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            color: AppColors.violet,
            icon: Icons.videocam_rounded,
            label: 'Video',
            active: selected == _MType.video,
            onTap: () => onSelect(_MType.video),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            color: AppColors.azure,
            icon: Icons.image_rounded,
            label: 'Photo',
            active: selected == _MType.photo,
            onTap: () => onSelect(_MType.photo),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  final Color color;
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.color,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.active
              ? widget.color.withValues(alpha: _pressed ? 0.20 : 0.13)
              : Colors.white.withValues(alpha: _pressed ? 0.08 : 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.active
                ? widget.color.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: AppTypography.label(
                size: 12,
                color: widget.active ? widget.color : AppColors.textMuted,
                weight: widget.active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stats card ───────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final String? diaryId;
  const _StatsCard({this.diaryId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DiaryStore.instance,
      builder: (_, _) {
        final ds = DiaryStore.instance;
        final diaries = diaryId != null
            ? ds.diaries.where((d) => d.id == diaryId).toList()
            : ds.diaries;

        int voice = 0, video = 0;
        final years = <int>{};
        for (final d in diaries) {
          for (final e in ds.entriesFor(d.id)) {
            if (e.type == 'voice') voice++;
            if (e.type == 'video') video++;
            years.add(e.createdAt.year);
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              _StatItem(value: '$voice', label: 'Voice notes'),
              _StatDivider(),
              _StatItem(value: '$video', label: 'Video clips'),
              _StatDivider(),
              _StatItem(
                  value: years.isEmpty ? '0' : '${years.length}',
                  label: 'Years'),
            ],
          ),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.display(size: 26).copyWith(
                color: AppColors.emberWarm, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: AppTypography.label(
                  size: 10.5, color: AppColors.textFaint)),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1, height: 36,
        color: Colors.white.withValues(alpha: 0.07),
      );
}

// ─── Memory Book banner ───────────────────────────────────────────────────────

class _BookBanner extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onShareTree;
  const _BookBanner({required this.onTap, this.onShareTree});

  @override
  State<_BookBanner> createState() => _BookBannerState();
}

class _BookBannerState extends State<_BookBanner> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final banner = GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.ember.withValues(alpha: _pressed ? 0.22 : 0.16),
              AppColors.emberWarm.withValues(alpha: _pressed ? 0.12 : 0.07),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.emberWarm
                .withValues(alpha: _pressed ? 0.42 : 0.28),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.ember.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.menu_book_rounded,
                  size: 20, color: AppColors.emberWarm),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Print your Memory Book',
                      style: AppTypography.body(
                          size: 15, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'All your moments, bound forever · from ₹399',
                    style: AppTypography.label(
                        size: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textFaint),
          ],
        ),
      ),
    );

    if (widget.onShareTree == null) return banner;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        banner,
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onShareTree!();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.ios_share_rounded,
                    size: 12,
                    color: AppColors.textFaint.withValues(alpha: 0.70)),
                const SizedBox(width: 6),
                Text(
                  'Share your tree →',
                  style: AppTypography.caption(
                    size: 12,
                    color: AppColors.textFaint.withValues(alpha: 0.70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Tree share card (off-screen, captured via RepaintBoundary) ───────────────

class _TreeShareCard extends StatelessWidget {
  final _Season season;
  final double health;
  final int monthCount;
  final ({int totalMoments, int yearsCount}) stats;

  const _TreeShareCard({
    super.key,
    required this.season,
    required this.health,
    required this.monthCount,
    required this.stats,
  });

  String get _seasonLabel => switch (season) {
        _Season.spring => 'Spring',
        _Season.summer => 'Summer',
        _Season.autumn => 'Autumn',
        _Season.winter => 'Winter',
      };

  String get _statsLine {
    final m = stats.totalMoments;
    final y = stats.yearsCount;
    final momentStr = '$m ${m == 1 ? 'moment' : 'moments'}';
    final yearStr = y == 0 ? '' : ' · $y ${y == 1 ? 'year' : 'years'}';
    return '$momentStr$yearStr · $_seasonLabel ${DateTime.now().year}';
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 400,
        height: 560,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.inkRaised, AppColors.ink, AppColors.inkDeep],
            ),
          ),
          child: Stack(
            children: [
              // Tree — static snapshot (breathe 0.5, fully revealed)
              Positioned(
                top: 24, left: 0, right: 0,
                height: 400,
                child: CustomPaint(
                  painter: _TreePainter(
                    breathe: 0.5,
                    revealProgress: 1.0,
                    season: season,
                    health: health,
                    monthCount: monthCount,
                  ),
                ),
              ),

              // Bottom bar: wordmark + stats
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.inkDeep.withValues(alpha: 0.95),
                      ],
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Saanjh wordmark
                      Text(
                        'Saanjh',
                        style: AppTypography.display(size: 20).copyWith(
                          color: AppColors.emberWarm.withValues(alpha: 0.80),
                        ),
                      ),
                      const Spacer(),
                      // Stats
                      Text(
                        _statsLine,
                        style: AppTypography.caption(
                          size: 11,
                          color: AppColors.textFaint,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
