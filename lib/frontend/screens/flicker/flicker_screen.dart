import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../../router/app_routes.dart';
import '../../state/diary_store.dart';
import '../../theme/app_spacing.dart';
import '../../state/flicker_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';

// ─── Phase ────────────────────────────────────────────────────────────────────

enum _Phase { ready, holding, sent, windowClosed }

// ─── Screen ───────────────────────────────────────────────────────────────────

class FlickerScreen extends StatefulWidget {
  /// When set: single-person mode — hold sends directly to this diary,
  /// bypassing the send sheet.
  final String? targetDiaryId;
  /// When true: shown as a tab in HomeScreen — hides back button,
  /// shows the Saanjh wordmark instead.
  final bool isEmbedded;
  const FlickerScreen({super.key, this.targetDiaryId, this.isEmbedded = false});

  @override
  State<FlickerScreen> createState() => _FlickerScreenState();
}

class _FlickerScreenState extends State<FlickerScreen>
    with TickerProviderStateMixin {
  final _store = FlickerStore.instance;
  final _diaryStore = DiaryStore.instance;

  List<DiaryContact> get _diaries => _diaryStore.diaries;

  DiaryContact? get _targetDiary {
    if (widget.targetDiaryId == null) return null;
    final m = _diaries.where((d) => d.id == widget.targetDiaryId);
    return m.isEmpty ? null : m.first;
  }

  late _Phase _phase;
  late final AnimationController _holdCtrl;
  late final AnimationController _breatheCtrl;
  late final AnimationController _burstCtrl;
  late final AnimationController _ritualCtrl;
  Offset _touchPoint = const Offset(0, 0);
  bool _h20 = false, _h50 = false, _h80 = false, _h93 = false;
  Timer? _heartbeatTimer; // rhythmic vibration during hold

  // Ritual state
  bool _showRitual = false;
  bool _ritualIsSingle = true;
  bool _ritualIsMutual = false;
  String _ritualContactName = '';

  // Accessibility: tap mode skips the hold gesture
  bool _flickerTapMode = false;

  @override
  void initState() {
    super.initState();
    _initPhase();
    _holdCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )
      ..addListener(_onHoldTick)
      ..addStatusListener(_onHoldStatus);
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    // Only animate when there's something to breathe for.
    if (_phase != _Phase.windowClosed) _breatheCtrl.repeat(reverse: true);
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _ritualCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // Re-derive phase when backend data arrives (e.g., already sent today).
    _store.addListener(_syncPhaseFromStore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openHaptic();
      _loadFlickerData();
    });
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _flickerTapMode = prefs.getBool('flicker_tap_mode') ?? false);
      }
    });
  }

  void _initPhase() {
    if (!_store.windowOpen) {
      _phase = _Phase.windowClosed;
    } else {
      final alreadySent = widget.targetDiaryId != null
          ? _store.hasMeFlickeredToday(widget.targetDiaryId!)
          : _diaries.any((d) => _store.hasMeFlickeredToday(d.id));
      _phase = alreadySent ? _Phase.sent : _Phase.ready;
    }
  }

  @override
  void dispose() {
    _store.removeListener(_syncPhaseFromStore);
    _holdCtrl.dispose();
    _breatheCtrl.dispose();
    _burstCtrl.dispose();
    _ritualCtrl.dispose();
    _stopVibration();
    super.dispose();
  }

  // When the store updates (e.g., backend data loaded), re-derive phase if
  // we haven't started interacting yet.
  void _syncPhaseFromStore() {
    if (!mounted || _phase != _Phase.ready) return;
    setState(_initPhase);
  }

  void _loadFlickerData() {
    final diaries = _diaries;
    if (diaries.isEmpty) return;
    _store.loadFlickerStatus(diaries);
  }

  Future<void> _openHaptic() async {
    if (!mounted) return;
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 220));
    await HapticFeedback.lightImpact();
  }

  void _onHoldTick() {
    final v = _holdCtrl.value;
    if (v >= 0.20 && !_h20) { _h20 = true; HapticFeedback.selectionClick(); }
    if (v >= 0.50 && !_h50) { _h50 = true; HapticFeedback.selectionClick(); }
    if (v >= 0.80 && !_h80) { _h80 = true; HapticFeedback.mediumImpact(); }
    if (v >= 0.93 && !_h93) { _h93 = true; HapticFeedback.lightImpact(); }
    if (mounted) setState(() {});
  }

  void _onHoldStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) _complete();
  }

  void _startHold(Offset local) {
    if (_phase != _Phase.ready) return;
    if (widget.targetDiaryId != null ? _targetDiary == null : _diaries.isEmpty) return;
    // Tap mode: skip the hold animation and complete immediately.
    if (_flickerTapMode) {
      _complete();
      return;
    }
    _touchPoint = local;
    _h20 = _h50 = _h80 = _h93 = false;
    _holdCtrl.forward(from: 0);
    setState(() => _phase = _Phase.holding);
    _startVibration();
  }

  void _cancelHold() {
    if (_phase != _Phase.holding) return;
    _stopVibration();
    _holdCtrl.reverse();
    setState(() => _phase = _Phase.ready);
  }

  // Lub-dub heartbeat pattern during hold.
  // Android: motor vibration in heartbeat rhythm (85ms lub + 80ms rest + 120ms dub + 600ms rest).
  // iOS: recursive haptic pulses matching the same rhythm.
  void _startVibration() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final hasVibrator = await Vibration.hasVibrator();
    if (!mounted || _phase != _Phase.holding) return; // guard async gap
    if (hasVibrator) {
      Vibration.vibrate(
        pattern: [0, 85, 80, 120, 600],
        repeat: 0, // loops indefinitely
      );
    } else {
      _scheduleHeartbeat();
    }
  }

  // Recursive iOS heartbeat — stops itself when hold ends.
  void _scheduleHeartbeat() {
    if (!mounted || _phase != _Phase.holding) return;
    HapticFeedback.mediumImpact(); // lub
    Future.delayed(const Duration(milliseconds: 160), () {
      if (!mounted || _phase != _Phase.holding) return;
      HapticFeedback.lightImpact(); // dub
      Future.delayed(const Duration(milliseconds: 700), _scheduleHeartbeat);
    });
  }

  void _stopVibration() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    Vibration.cancel();
  }

  Future<void> _complete() async {
    _stopVibration();
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.lightImpact();

    _burstCtrl.forward(from: 0);
    if (!mounted) return;

    if (widget.targetDiaryId != null) {
      // Single-person mode: send directly then show ritual.
      final t = _targetDiary;
      if (t != null) _store.sendFlickerToMany([t.id], [t.name]);
      _triggerRitual(
        isSingle: true,
        isMutual: t != null && _store.isMutualToday(t.id),
        contactName: t?.displayName.split(' ').first ?? '',
      );
    } else {
      // Normal mode: send sheet.
      await Future.delayed(const Duration(milliseconds: 380));
      if (!mounted) return;
      await _showSendSheet();
    }
  }

  void _triggerRitual({
    required bool isSingle,
    required bool isMutual,
    required String contactName,
  }) {
    if (!mounted) return;
    _ritualIsSingle = isSingle;
    _ritualIsMutual = isMutual;
    _ritualContactName = contactName;
    // Lub-dub haptic
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) HapticFeedback.lightImpact();
    });
    setState(() => _showRitual = true);
    _ritualCtrl.forward(from: 0).whenComplete(() {
      if (mounted) {
        _breatheCtrl.stop();
        setState(() { _showRitual = false; _phase = _Phase.sent; });
      }
    });
  }

  Future<void> _showSendSheet() async {
    List<DiaryContact>? sentContacts;

    final sent = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder: (_) => _SendSheet(
        diaries: _diaries,
        store: _store,
        onSend: (selected) {
          _store.sendFlickerToMany(
            selected.map((d) => d.id).toList(),
            selected.map((d) => d.name).toList(),
          );
          sentContacts = selected;
          Navigator.pop(context, true);
        },
      ),
    );

    if (!mounted) return;
    if (sent == true) {
      final contacts = sentContacts ?? [];
      final isMutual = contacts.any((c) => _store.isMutualToday(c.id));
      final firstName = contacts.length == 1
          ? contacts.first.displayName.split(' ').first
          : '';
      _triggerRitual(
        isSingle: contacts.length == 1,
        isMutual: isMutual,
        contactName: firstName,
      );
    } else {
      // Dismissed without sending — quietly reset.
      _burstCtrl.reverse();
      setState(() => _phase = _Phase.ready);
    }
  }

  bool get _anyMutual => widget.targetDiaryId != null
      ? _store.isMutualToday(widget.targetDiaryId!)
      : _diaries.any((d) => _store.isMutualToday(d.id));
  bool get _anyReceived => widget.targetDiaryId != null
      ? _store.hasThemFlickeredToday(widget.targetDiaryId!)
      : _diaries.any((d) => _store.hasThemFlickeredToday(d.id));
  // At-risk = final 1 hour of the day (11 PM – midnight) AND not yet sent.
  // Deliberately NOT tied to the voice-note diary streak — that is a separate
  // concept and would show false urgency from day 2 of a diary streak onwards.
  bool get _anyAtRisk {
    if (_phase == _Phase.sent) return false;
    if (_diaries.isEmpty) return false;
    final alreadySent = widget.targetDiaryId != null
        ? _store.hasMeFlickeredToday(widget.targetDiaryId!)
        : _diaries.any((d) => _store.hasMeFlickeredToday(d.id));
    if (alreadySent) return false;
    return _store.windowState == FlickerWindowState.lastChance;
  }

  // First received pulse for today — used in windowClosed state.
  FlickerRecord? get _firstReceivedPulse {
    if (widget.targetDiaryId != null) {
      return _store.receivedToday(widget.targetDiaryId!);
    }
    for (final d in _diaries) {
      final r = _store.receivedToday(d.id);
      if (r != null) return r;
    }
    return null;
  }

  // Best diary to navigate to for the windowClosed voice-note CTA.
  String? get _ctaDiaryId =>
      widget.targetDiaryId ?? (_diaries.isNotEmpty ? _diaries.first.id : null);

  DiaryContact? get _bestDiary {
    if (widget.targetDiaryId != null) return _targetDiary;
    if (_diaries.isEmpty) return null;
    return _diaries.reduce((a, b) =>
        DiaryStore.instance.streakDays(a.id) >= DiaryStore.instance.streakDays(b.id) ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.inkDeep,
      body: ListenableBuilder(
        listenable: Listenable.merge([_store, _diaryStore]),
        builder: (_, w) {
          return Stack(
            children: [
              // ── Breathing ambient background ─────────────────────────────
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _breatheCtrl,
                    builder: (_, w) => CustomPaint(
                      painter: _FlickerBgPainter(
                        phase: _phase,
                        breathe: _breatheCtrl.value,
                        anyReceived: _anyReceived,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Burst particles on send ──────────────────────────────────
              if (_burstCtrl.value > 0)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _burstCtrl,
                    builder: (_, w) => CustomPaint(
                      painter: _BurstPainter(
                        progress: _burstCtrl.value,
                        isMutual: _anyMutual,
                      ),
                    ),
                  ),
                ),

              // ── Main content ─────────────────────────────────────────────
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(
                      onClose: widget.isEmbedded ? null : () => context.pop(),
                      isEmbedded: widget.isEmbedded,
                    ),

                    const Spacer(),

                    // Single-person context badge
                    if (_targetDiary != null) ...[
                      _ForPersonBadge(contact: _targetDiary!),
                      const SizedBox(height: 20),
                    ],

                    // The hold button — the ritual centre
                    Semantics(
                      label: _flickerTapMode
                          ? 'Tap to flicker'
                          : 'Hold to flicker',
                      button: true,
                      child: _HoldButton(
                        phase: _phase,
                        holdProgress: _holdCtrl.value,
                        breatheValue: _breatheCtrl.value,
                        touchPoint: _touchPoint,
                        atRisk: _anyAtRisk,
                        isMutual: _anyMutual,
                        theyPulsed: _anyReceived,
                        windowClosed: _phase == _Phase.windowClosed,
                        onPressDown: _startHold,
                        onPressUp: _cancelHold,
                        onPressCancel: _cancelHold,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── windowClosed: emotional re-engagement content ─────────
                    if (_phase == _Phase.windowClosed) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 36),
                        child: Column(
                          children: [
                            // 1. Heading
                            Text(
                              'Already with you today.',
                              style: AppTypography.title(size: 22)
                                  .copyWith(fontStyle: FontStyle.italic),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            // 2. Sub-text
                            Text(
                              'Come back tomorrow to flicker again.',
                              style: AppTypography.serifItalic(
                                size: 15,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            // 3. Received pulse — shown if they pulsed us today
                            if (_firstReceivedPulse != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                '💛 ${_firstReceivedPulse!.personName} flickered for you'
                                ' at ${_firstReceivedPulse!.timeLabel}',
                                style: AppTypography.label(
                                  size: 14,
                                  color: AppColors.emberBright
                                      .withValues(alpha: 0.80),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 28),
                            // 4. Voice note CTA — redirects energy constructively
                            if (_ctaDiaryId != null)
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  context.push(
                                    AppRoutes.voiceRecord,
                                    extra: {
                                      'isVideo': false,
                                      'targetDiaryId': _ctaDiaryId,
                                    },
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.ember
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: AppColors.emberWarm
                                          .withValues(alpha: 0.28),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.mic_rounded,
                                          size: 16,
                                          color: AppColors.emberWarm),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Meanwhile, record a voice note →',
                                        style: AppTypography.label(
                                          size: 13,
                                          color: AppColors.emberWarm,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // ── Normal states: standard label + hints ─────────────
                      _ButtonLabel(
                        phase: _phase,
                        totalCount: _diaries.length,
                        atRisk: _anyAtRisk,
                        isMutual: _anyMutual,
                        targetName: _targetDiary?.name.split(' ').first,
                      ),
                      if (_flickerTapMode) ...[
                        const SizedBox(height: 6),
                        Text(
                          '(Tap mode)',
                          style: AppTypography.label(
                            size: 11,
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                      ],

                      // No connections — invite to add
                      if (_diaries.isEmpty && _phase == _Phase.ready) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Add someone to start flickering.',
                          style: AppTypography.serifItalic(
                            size: 15,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              context.push(AppRoutes.connectFirst),
                          child: Text(
                            'Add →',
                            style: AppTypography.label(
                              size: 14,
                              color: AppColors.emberWarm,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],

                      // Midnight hint deferred until ritual + burst both complete
                      if (_phase == _Phase.sent &&
                          _burstCtrl.status ==
                              AnimationStatus.completed) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Opens again at midnight',
                          style: AppTypography.label(
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.20)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],

                    const Spacer(),

                    if (_bestDiary != null)
                      _StreakLine(diary: _bestDiary!),

                    SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 28),
                  ],
                ),
              ),

              // ── Ritual overlay — on top of burst and content ─────────────
              if (_showRitual)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _ritualCtrl,
                    builder: (_, _) => _RitualOverlay(
                      progress: _ritualCtrl.value,
                      isSingle: _ritualIsSingle,
                      isMutual: _ritualIsMutual,
                      contactName: _ritualContactName,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Flicker background painter ─────────────────────────────────────────────────
// A single breathing orb at the bottom of the screen. Grows and brightens as
// you hold. No fire — just warmth and presence.

class _FlickerBgPainter extends CustomPainter {
  final _Phase phase;
  final double breathe;
  final bool anyReceived;

  _FlickerBgPainter({
    required this.phase,
    required this.breathe,
    required this.anyReceived,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Received-pulse warm flush at top when someone pulsed us
    if (anyReceived && phase != _Phase.sent) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.emberWarm.withValues(alpha: 0.04 + breathe * 0.015),
              Colors.transparent,
            ],
          ).createShader(Offset.zero & size),
      );
    }
  }

  @override
  bool shouldRepaint(_FlickerBgPainter o) =>
      o.phase != phase ||
      o.breathe != breathe ||
      o.anyReceived != anyReceived;
}

// ─── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final VoidCallback? onClose;
  final bool isEmbedded;
  const _TopBar({this.onClose, this.isEmbedded = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: isEmbedded
          // Embedded: show app wordmark instead of back button
          ? Text(
              'Saanjh',
              style: AppTypography.display(size: 22).copyWith(
                color: AppColors.emberWarm.withValues(alpha: 0.70),
              ),
            )
          : GestureDetector(
              onTap: onClose,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10), width: 1),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
    );
  }
}

// ─── Send sheet (Snapchat-style: hold first, choose who after) ────────────────

class _SendSheet extends StatefulWidget {
  final List<DiaryContact> diaries;
  final FlickerStore store;
  final void Function(List<DiaryContact> selected) onSend;

  const _SendSheet({
    required this.diaries,
    required this.store,
    required this.onSend,
  });

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    // All selected by default — most common intent.
    _selectedIds = widget.diaries.map((d) => d.id).toSet();
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        if (_selectedIds.length > 1) _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = _selectedIds.length == widget.diaries.length;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.l, AppSpacing.xl, AppSpacing.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Text('Who feels it?', style: AppTypography.title(size: 22)),
              const SizedBox(height: 6),
              Text(
                'Your flicker is ready — choose who feels it.',
                style: AppTypography.serifItalic(size: 14)
                    .copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Contact tiles
              for (final diary in widget.diaries) ...[
                _ContactTile(
                  contact: diary,
                  isSelected: _selectedIds.contains(diary.id),
                  alreadySent: widget.store.hasMeFlickeredToday(diary.id),
                  theyPulsed: widget.store.hasThemFlickeredToday(diary.id),
                  onTap: () => _toggle(diary.id),
                ),
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 16),

              // Send CTA
              GestureDetector(
                onTap: () {
                  final selected = widget.diaries
                      .where((d) => _selectedIds.contains(d.id))
                      .toList();
                  widget.onSend(selected);
                },
                child: Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: AppColors.emberGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppShadows.emberGlow(intensity: 0.45, blur: 24),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite_rounded,
                            size: 17, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(
                          all
                              ? 'Send to everyone'
                              : 'Send to ${_selectedIds.length} ${_selectedIds.length == 1 ? "person" : "people"}',
                          style: AppTypography.button(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final DiaryContact contact;
  final bool isSelected;
  final bool alreadySent;
  final bool theyPulsed;
  final VoidCallback onTap;

  const _ContactTile({
    required this.contact,
    required this.isSelected,
    required this.alreadySent,
    required this.theyPulsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMutual = alreadySent && theyPulsed;
    final String sub;
    final Color subColor;
    if (isMutual) {
      sub = 'mutual today ♥';
      subColor = const Color(0xFF7CD992);
    } else if (theyPulsed && !alreadySent) {
      sub = 'was here · send yours back';
      subColor = AppColors.emberBright;
    } else if (alreadySent) {
      sub = 'already felt your flicker';
      subColor = AppColors.textMuted;
    } else {
      sub = 'waiting for your flicker';
      subColor = AppColors.textMuted;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.ember.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.emberWarm.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    contact.avatarColor,
                    contact.avatarColor.withValues(alpha: 0.70),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: isSelected
                      ? AppColors.emberWarm.withValues(alpha: 0.50)
                      : Colors.white.withValues(alpha: 0.10),
                  width: isSelected ? 1.5 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.emberWarm.withValues(alpha: 0.22),
                          blurRadius: 14,
                        )
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  contact.initial,
                  style: AppTypography.title(size: 18).copyWith(
                    color: Colors.white,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Name + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style:
                        AppTypography.body(size: 15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: AppTypography.label(size: 12, color: subColor)),
                ],
              ),
            ),

            // Checkbox
            AnimatedContainer(
              duration: AppMotion.fast,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.emberWarm
                    : Colors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: isSelected
                      ? AppColors.emberWarm
                      : Colors.white.withValues(alpha: 0.12),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}


// ─── Hold button ──────────────────────────────────────────────────────────────

class _HoldButton extends StatelessWidget {
  final _Phase phase;
  final double holdProgress;
  final double breatheValue;
  final Offset touchPoint;
  final bool atRisk;
  final bool isMutual;
  final bool theyPulsed;
  final bool windowClosed;
  final void Function(Offset) onPressDown;
  final VoidCallback onPressUp;
  final VoidCallback onPressCancel;

  static const _r = 68.0;

  const _HoldButton({
    required this.phase,
    required this.holdProgress,
    required this.breatheValue,
    required this.touchPoint,
    required this.atRisk,
    required this.isMutual,
    required this.theyPulsed,
    required this.windowClosed,
    required this.onPressDown,
    required this.onPressUp,
    required this.onPressCancel,
  });

  @override
  Widget build(BuildContext context) {
    final idle = phase == _Phase.ready;
    final holding = phase == _Phase.holding;
    final sent = phase == _Phase.sent;

    final breathScale = idle
        ? 1.0 + 0.030 * breatheValue
        : holding
            ? 1.0 + holdProgress * 0.06
            : 1.0;

    return GestureDetector(
      onPanDown: (windowClosed || sent)
          ? null
          : (d) => onPressDown(d.localPosition),
      onPanEnd: (windowClosed || sent) ? null : (_) => onPressUp(),
      onPanCancel: (windowClosed || sent) ? null : onPressCancel,
      child: AnimatedScale(
        scale: breathScale,
        duration: const Duration(milliseconds: 80),
        child: SizedBox(
          width: _r * 2 + 80,
          height: _r * 2 + 80,
          child: CustomPaint(
            painter: _HoldPainter(
              phase: phase,
              holdProgress: holdProgress,
              breathe: breatheValue,
              touchPoint: touchPoint + const Offset(40, 40),
              buttonRadius: _r,
              atRisk: atRisk,
              isMutual: isMutual,
            ),
            child: Center(
              child: _ButtonCore(
                phase: phase,
                holdProgress: holdProgress,
                atRisk: atRisk,
                isMutual: isMutual,
                windowClosed: windowClosed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoldPainter extends CustomPainter {
  final _Phase phase;
  final double holdProgress;
  final double breathe;
  final Offset touchPoint;
  final double buttonRadius;
  final bool atRisk;
  final bool isMutual;

  _HoldPainter({
    required this.phase,
    required this.holdProgress,
    required this.breathe,
    required this.touchPoint,
    required this.buttonRadius,
    required this.atRisk,
    required this.isMutual,
  });

  Color get _accent => isMutual
      ? AppColors.successGreen
      : atRisk
          ? AppColors.destructive
          : AppColors.emberWarm;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = buttonRadius;

    final glowAlpha = switch (phase) {
      _Phase.ready        => 0.09 + 0.06 * breathe,
      _Phase.holding      => 0.14 + holdProgress * 0.24,
      _Phase.sent         => 0.30,
      _Phase.windowClosed => 0.07 + 0.06 * breathe, // dim but still breathing
    };

    // Ambient glow rings
    for (int i = 3; i >= 1; i--) {
      canvas.drawCircle(
        center,
        r + i * 16.0 + breathe * 5,
        Paint()
          ..color = _accent.withValues(alpha: glowAlpha / i)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14.0 * i),
      );
    }

    // Outer halo (sent / mutual)
    if (phase == _Phase.sent || isMutual) {
      canvas.drawCircle(
        center, r + 8,
        Paint()
          ..color = _accent.withValues(alpha: 0.50)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Base fill
    final baseAlpha = switch (phase) {
      _Phase.ready        => 0.13,
      _Phase.holding      => 0.18 + holdProgress * 0.18,
      _Phase.sent         => 0.30,
      _Phase.windowClosed => 0.30, // dim heartbeat orb as specified
    };
    canvas.drawCircle(center, r,
        Paint()..color = _accent.withValues(alpha: baseAlpha));

    // Border ring
    canvas.drawCircle(
      center, r,
      Paint()
        ..color = _accent.withValues(
            alpha: phase == _Phase.sent
                ? 0.80
                : 0.26 + holdProgress * 0.44)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Radial fill from touch point during hold
    if (phase == _Phase.holding && holdProgress > 0) {
      final fill = r * 2.6 * holdProgress;
      canvas.save();
      canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: center, radius: r - 1)));
      canvas.drawCircle(
        touchPoint, fill,
        Paint()
          ..color = _accent.withValues(alpha: 0.40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.restore();
    }

    // Arc progress ring
    if (phase == _Phase.holding && holdProgress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r + 4),
        -math.pi / 2,
        2 * math.pi * holdProgress,
        false,
        Paint()
          ..color = _accent.withValues(alpha: 0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_HoldPainter o) => true;
}

class _ButtonCore extends StatelessWidget {
  final _Phase phase;
  final double holdProgress;
  final bool atRisk;
  final bool isMutual;
  final bool windowClosed;

  const _ButtonCore({
    required this.phase,
    required this.holdProgress,
    required this.atRisk,
    required this.isMutual,
    required this.windowClosed,
  });

  @override
  Widget build(BuildContext context) {
    // windowClosed: orb is rendered at 30% fill by _HoldPainter — interior is
    // intentionally empty so the calm glow communicates rest, not blockage.
    if (windowClosed) return const SizedBox.shrink();

    if (phase == _Phase.sent) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMutual ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 32,
            color: isMutual ? AppColors.successGreen : AppColors.emberWarm,
          ),
          const SizedBox(height: 4),
          Text(
            'Flickered',
            style: AppTypography.label(
                size: 11,
                weight: FontWeight.w700,
                color: isMutual
                    ? const Color(0xFF7CD992)
                    : AppColors.emberBright),
          ),
        ],
      );
    }

    if (phase == _Phase.holding) {
      return Text(
        '${(holdProgress * 100).round()}',
        style: AppTypography.display(size: 28).copyWith(
            color: Colors.white
                .withValues(alpha: 0.28 + holdProgress * 0.72)),
      );
    }

    // Ready
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          atRisk ? Icons.warning_amber_rounded : Icons.favorite_rounded,
          size: 30,
          color: atRisk
              ? AppColors.destructive
              : AppColors.emberWarm.withValues(alpha: 0.82),
        ),
        const SizedBox(height: 4),
        Text('Hold',
            style: AppTypography.label(
                size: 11,
                color: Colors.white.withValues(alpha: 0.32))),
      ],
    );
  }
}

// ─── Label under button ───────────────────────────────────────────────────────

class _ButtonLabel extends StatelessWidget {
  final _Phase phase;
  final int totalCount;
  final bool atRisk;
  final bool isMutual;
  final String? targetName;

  const _ButtonLabel({
    required this.phase,
    required this.totalCount,
    required this.atRisk,
    required this.isMutual,
    this.targetName,
  });

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (phase) {
      _Phase.windowClosed => (
          'Opens again at midnight',
          Colors.white.withValues(alpha: 0.25),
        ),
      _Phase.sent => isMutual
          ? (
              'You\'re both here today ♥',
              const Color(0xFF7CD992),
            )
          : (
              'They felt your flicker.',
              AppColors.emberBright,
            ),
      _Phase.holding => (
          'Almost there…',
          Colors.white.withValues(alpha: 0.52),
        ),
      _Phase.ready => atRisk
          ? (
              '⚠ Last chance — flicker before midnight',
              const Color(0xFFFF8A82),
            )
          : totalCount == 0
              ? (
                  'Add connections to begin',
                  Colors.white.withValues(alpha: 0.28),
                )
              : targetName != null
                  ? (
                      'Hold to flicker for $targetName',
                      Colors.white.withValues(alpha: 0.38),
                    )
                  : (
                      'Hold to flicker',
                      Colors.white.withValues(alpha: 0.38),
                    ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: AnimatedSwitcher(
        duration: AppMotion.medium,
        child: Text(
          text,
          key: ValueKey(phase),
          style: AppTypography.body(size: 14, color: color),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ─── Single-person context badge ─────────────────────────────────────────────

class _ForPersonBadge extends StatelessWidget {
  final DiaryContact contact;
  const _ForPersonBadge({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                contact.avatarColor,
                contact.avatarColor.withValues(alpha: 0.70),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: AppColors.emberWarm.withValues(alpha: 0.40),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.emberWarm.withValues(alpha: 0.22),
                blurRadius: 10,
              ),
            ],
          ),
          child: Center(
            child: Text(
              contact.initial,
              style: AppTypography.label(
                size: 13,
                weight: FontWeight.w600,
              ).copyWith(color: Colors.white, fontStyle: FontStyle.italic),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'for ${contact.name.split(' ').first}',
          style: AppTypography.serifItalic(size: 15)
              .copyWith(color: Colors.white.withValues(alpha: 0.45)),
        ),
      ],
    );
  }
}

// ─── Streak line ──────────────────────────────────────────────────────────────
// One quiet line of context — not a dashboard.

class _StreakLine extends StatelessWidget {
  final DiaryContact diary;
  const _StreakLine({required this.diary});

  @override
  Widget build(BuildContext context) {
    final days = DiaryStore.instance.streakDays(diary.id);
    final hasStreak = days > 0;

    final text = days == 0
        ? 'Your first morning together'
        : days == 1
            ? '1 morning with ${diary.name.split(' ').first}'
            : '$days mornings with ${diary.name.split(' ').first}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hasStreak) ...[
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.emberWarm.withValues(alpha: 0.40),
              boxShadow: [
                BoxShadow(
                  color: AppColors.emberWarm.withValues(alpha: 0.30),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          text,
          style: AppTypography.serifItalic(size: 14).copyWith(
            color: Colors.white
                .withValues(alpha: hasStreak ? 0.36 : 0.22),
          ),
        ),
        if (hasStreak) ...[
          const SizedBox(width: 10),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.emberWarm.withValues(alpha: 0.40),
              boxShadow: [
                BoxShadow(
                  color: AppColors.emberWarm.withValues(alpha: 0.30),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Ritual overlay ───────────────────────────────────────────────────────────
// Full-screen closing ceremony shown immediately after flicker is sent.
// Sits above burst particles (burst still paints beneath).

class _RitualOverlay extends StatelessWidget {
  final double progress; // 0.0 → 1.0 over 600ms
  final bool isSingle;
  final bool isMutual;
  final String contactName;

  const _RitualOverlay({
    required this.progress,
    required this.isSingle,
    required this.isMutual,
    required this.contactName,
  });

  double get _peakAlpha => isMutual ? 0.12 : (isSingle ? 0.15 : 0.20);
  Color get _washColor =>
      isMutual ? AppColors.successGreen : AppColors.ember;
  Color get _textColor =>
      isMutual ? const Color(0xFF7CD992) : AppColors.emberWarm;

  String get _message {
    if (isMutual) return 'You\'re both here today. ♥';
    if (isSingle) return '$contactName felt your flicker.';
    return 'They all felt your flicker. 💛';
  }

  // Wash: 0→peak over first 35%, hold to 50%, peak→0 over last 50%.
  double _washAlpha(double t) {
    final p = _peakAlpha;
    if (t < 0.35) return p * (t / 0.35);
    if (t < 0.50) return p;
    return p * (1.0 - (t - 0.50) / 0.50);
  }

  // Text fades in starting at ~33% (200ms of 600ms).
  double _textOpacity(double t) {
    if (t < 0.33) return 0.0;
    return ((t - 0.33) / 0.30).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Colour wash
        Positioned.fill(
          child: ColoredBox(
            color: _washColor.withValues(alpha: _washAlpha(progress)),
          ),
        ),

        // Mutual: two concentric rings expanding from centre
        if (isMutual)
          Positioned.fill(
            child: CustomPaint(
              painter: _MutualCirclesPainter(progress: progress),
            ),
          ),

        // Centred message — fades in at 200ms
        Center(
          child: Opacity(
            opacity: _textOpacity(progress),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _message,
                style: AppTypography.serifItalic(
                  size: 28,
                  color: _textColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MutualCirclesPainter extends CustomPainter {
  final double progress;
  const _MutualCirclesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const maxR = 200.0;

    // Two rings expanding at different speeds.
    for (final (delay, speed) in [(0.0, 1.0), (0.15, 0.7)]) {
      final t = ((progress - delay) / (1.0 - delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final r = maxR * t * speed;
      final alpha = (0.30 * (1.0 - t)).clamp(0.0, 0.30);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = AppColors.successGreen.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_MutualCirclesPainter old) => old.progress != progress;
}

// ─── Burst painter ────────────────────────────────────────────────────────────

class _BurstPainter extends CustomPainter {
  final double progress;
  final bool isMutual;
  _BurstPainter({required this.progress, required this.isMutual});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final rng = math.Random(42);
    final cx = size.width / 2;
    final cy = size.height * 0.42;

    final colors = isMutual
        ? [
            AppColors.successGreen,
            const Color(0xFF7CD992),
            AppColors.emberWarm,
            Colors.white,
          ]
        : [
            AppColors.emberWarm,
            AppColors.emberBright,
            AppColors.ember,
            Colors.white,
          ];

    for (int i = 0; i < 32; i++) {
      final angle =
          (i / 32) * 2 * math.pi + rng.nextDouble() * 0.18;
      final speed = 80.0 + rng.nextDouble() * 200;
      final dist = speed * progress;
      final alpha = (1.0 - progress) * 0.88;
      final r = 1.8 + rng.nextDouble() * 5.5;
      canvas.drawCircle(
        Offset(cx + dist * math.cos(angle),
            cy + dist * math.sin(angle)),
        r * (1 - progress * 0.35),
        Paint()
          ..color = colors[i % colors.length].withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter o) =>
      o.progress != progress || o.isMutual != isMutual;
}

