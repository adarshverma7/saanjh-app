import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../services/share_card_service.dart';
import '../../state/diary_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/saanjh_empty_state.dart';
import '../../widgets/saanjh_stagger.dart';
import '../../widgets/voice_share_card.dart';

class MemoryJarScreen extends StatefulWidget {
  const MemoryJarScreen({super.key});

  @override
  State<MemoryJarScreen> createState() => _MemoryJarScreenState();
}

class _MemoryJarScreenState extends State<MemoryJarScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveCtrl;

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

  // Collect all jarred entries, grouped by contact.
  List<({DiaryContact diary, List<DiaryEntry> entries})> _grouped() {
    final store = DiaryStore.instance;
    final result = <({DiaryContact diary, List<DiaryEntry> entries})>[];
    for (final diary in store.diaries) {
      final jarredIds = store.jarredFor(diary.id);
      if (jarredIds.isEmpty) continue;
      final allEntries = store.entriesFor(diary.id);
      final jarred = allEntries
          .where((e) => jarredIds.contains(e.id))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (jarred.isNotEmpty) result.add((diary: diary, entries: jarred));
    }
    return result;
  }

  void _removeFromJar(DiaryContact diary, DiaryEntry entry) {
    HapticFeedback.mediumImpact();
    DiaryStore.instance.unjarEntry(diary.id, entry.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: ListenableBuilder(
        listenable: DiaryStore.instance,
        builder: (_, _) {
          final groups = _grouped();
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(),
                const SizedBox(height: 8),
                Expanded(
                  child: groups.isEmpty
                      ? _EmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                          itemCount: groups.length,
                          itemBuilder: (_, gi) {
                            final group = groups[gi];
                            return SaanjhStaggerItem(
                              key: ValueKey(group.diary.id),
                              index: gi,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (gi > 0) const SizedBox(height: 24),
                                  _GroupHeader(diary: group.diary),
                                  const SizedBox(height: 10),
                                  ...group.entries.map(
                                    (e) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _JarEntryTile(
                                        diary: group.diary,
                                        entry: e,
                                        waveCtrl: _waveCtrl,
                                        onRemove: () =>
                                            _removeFromJar(group.diary, e),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: AppColors.textMuted),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('✨ Memory Jar', style: AppTypography.title(size: 22)),
              Text(
                'Your favourite voice moments',
                style:
                    AppTypography.label(size: 12, color: AppColors.textFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatefulWidget {
  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SaanjhEmptyState(
      visual: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => SizedBox(
          width: 100,
          height: 130,
          child: CustomPaint(
            painter: _JarPainter(_ctrl.value),
          ),
        ),
      ),
      title: 'Your jar is empty.',
      body: 'Long-press any voice note and save it here. ✨',
    );
  }
}

class _JarPainter extends CustomPainter {
  final double breathe; // 0.0 → 1.0

  const _JarPainter(this.breathe);

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = 0.25 + breathe * 0.10;
    final paint = Paint()
      ..color = AppColors.emberWarm.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;

    // Jar body (tall oval)
    final bodyRect = Rect.fromCenter(
      center: Offset(cx, size.height * 0.62),
      width: size.width * 0.72,
      height: size.height * 0.65,
    );
    canvas.drawOval(bodyRect, paint);

    // Neck
    final neckTop = size.height * 0.26;
    final neckBottom = size.height * 0.30;
    final neckW = size.width * 0.42;
    canvas.drawLine(
      Offset(cx - neckW / 2, neckTop),
      Offset(cx - neckW / 2 - 4, neckBottom),
      paint,
    );
    canvas.drawLine(
      Offset(cx + neckW / 2, neckTop),
      Offset(cx + neckW / 2 + 4, neckBottom),
      paint,
    );
    canvas.drawLine(
      Offset(cx - neckW / 2 - 4, neckBottom),
      Offset(cx + neckW / 2 + 4, neckBottom),
      paint,
    );

    // Lid (rounded rect)
    final lidTop = size.height * 0.10;
    final lidLeft = cx - size.width * 0.28;
    final lidRight = cx + size.width * 0.28;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(lidLeft, lidTop, lidRight, neckTop),
        const Radius.circular(6),
      ),
      paint,
    );

    // ✨ faint glow inside
    canvas.drawOval(
      bodyRect.deflate(12),
      Paint()
        ..color = AppColors.emberWarm.withValues(alpha: breathe * 0.08)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
  }

  @override
  bool shouldRepaint(_JarPainter old) => old.breathe != breathe;
}

// ─── Group header ─────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  final DiaryContact diary;
  const _GroupHeader({required this.diary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: diary.avatarColor.withValues(alpha: 0.25),
          ),
          child: Center(
            child: Text(
              diary.initial,
              style: AppTypography.label(size: 11, color: diary.avatarColor),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          diary.displayName,
          style: AppTypography.label(
              size: 13,
              weight: FontWeight.w600,
              color: AppColors.text),
        ),
      ],
    );
  }
}

// ─── Entry tile ───────────────────────────────────────────────────────────────

class _JarEntryTile extends StatefulWidget {
  final DiaryContact diary;
  final DiaryEntry entry;
  final AnimationController waveCtrl;
  final VoidCallback onRemove;

  const _JarEntryTile({
    required this.diary,
    required this.entry,
    required this.waveCtrl,
    required this.onRemove,
  });

  @override
  State<_JarEntryTile> createState() => _JarEntryTileState();
}

class _JarEntryTileState extends State<_JarEntryTile> {
  bool _isPlaying = false;
  bool _sharing = false;
  final _cardKey = GlobalKey();

  String get _dateLabel {
    final d = widget.entry.createdAt;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    await ShareCardService.instance
        .shareVoiceCard(_cardKey, widget.diary.displayName);
    if (mounted) setState(() => _sharing = false);
  }

  void _onLongPress() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _JarEntryActionsSheet(
        onReact: () {
          Navigator.pop(context);
          context.push(AppRoutes.voiceRecord, extra: {
            'isVideo': false,
            'autoStart': true,
            'targetDiaryId': widget.diary.id,
            'parentEntryId': widget.entry.id,
            'reactionContext':
                'Reacting to a memory from ${widget.diary.displayName}',
          });
        },
        onShare: () {
          Navigator.pop(context);
          _share();
        },
        onRemove: () {
          Navigator.pop(context);
          widget.onRemove();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Off-screen share card — zero layout size
        Offstage(
          child: VoiceShareCard(
            key: _cardKey,
            contactName: widget.diary.displayName,
            duration: '', // duration not available in DiaryEntry; kept empty
            createdAt: widget.entry.createdAt,
            seed: widget.entry.id.hashCode.abs(),
          ),
        ),
        GestureDetector(
          onLongPress: _onLongPress,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.ember.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.emberWarm.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.diary.avatarColor.withValues(alpha: 0.20),
                  ),
                  child: Center(
                    child: Text(
                      widget.diary.initial,
                      style: AppTypography.label(
                          size: 14, color: widget.diary.avatarColor),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.entry.type == 'video'
                            ? '🎬 Video note'
                            : '🎙 Voice note',
                        style: AppTypography.label(
                            size: 13, color: AppColors.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dateLabel,
                        style: AppTypography.label(
                            size: 11, color: AppColors.textFaint),
                      ),
                      if (widget.entry.transcript != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '"${widget.entry.transcript}"',
                          style: AppTypography.body(
                              size: 12, color: AppColors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Play button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isPlaying = !_isPlaying);
                  },
                  child: _isPlaying
                      ? AnimatedBuilder(
                          animation: widget.waveCtrl,
                          builder: (_, _) => _MiniWave(ctrl: widget.waveCtrl),
                        )
                      : Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.ember.withValues(alpha: 0.20),
                            border: Border.all(
                              color:
                                  AppColors.emberWarm.withValues(alpha: 0.40),
                            ),
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              size: 18, color: AppColors.emberWarm),
                        ),
                ),
              ],
            ),
          ),
        ),
        // Sharing indicator overlay
        if (_sharing)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.emberWarm,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniWave extends StatelessWidget {
  final AnimationController ctrl;
  const _MiniWave({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(5, (i) {
          final phase = math.sin((ctrl.value + i * 0.2) * math.pi * 2);
          final h = (4.0 + phase.abs() * 14).clamp(3.0, 18.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Container(
              width: 3,
              height: h,
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

// ─── Jar entry actions sheet (React + Remove) ─────────────────────────────────

class _JarEntryActionsSheet extends StatelessWidget {
  final VoidCallback onReact;
  final VoidCallback onShare;
  final VoidCallback onRemove;
  const _JarEntryActionsSheet({
    required this.onReact,
    required this.onShare,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              ListTile(
                leading: const Text('🎙', style: TextStyle(fontSize: 20)),
                title: Text('React with your voice',
                    style: AppTypography.body(size: 15)),
                onTap: onReact,
                contentPadding: EdgeInsets.zero,
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded,
                    color: AppColors.emberWarm),
                title: Text('Share →',
                    style: AppTypography.body(size: 15)),
                onTap: onShare,
                contentPadding: EdgeInsets.zero,
              ),
              ListTile(
                leading: const Icon(Icons.star_border_rounded,
                    color: Colors.redAccent),
                title: Text('Remove from Memory Jar',
                    style: AppTypography.body(
                        size: 15, color: Colors.redAccent)),
                onTap: onRemove,
                contentPadding: EdgeInsets.zero,
              ),
              ListTile(
                leading:
                    Icon(Icons.close_rounded, color: AppColors.textMuted),
                title: Text('Cancel',
                    style: AppTypography.body(
                        size: 15, color: AppColors.textMuted)),
                onTap: () => Navigator.pop(context),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

