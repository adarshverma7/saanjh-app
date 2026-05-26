import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../router/app_routes.dart';
import '../services/morning_service.dart';
import '../state/diary_store.dart';
import '../state/flicker_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';

class MorningOverlay extends StatefulWidget {
  const MorningOverlay({super.key});

  @override
  State<MorningOverlay> createState() => _MorningOverlayState();
}

class _MorningOverlayState extends State<MorningOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _holdCtrl;
  late final AnimationController _breatheCtrl;
  bool _pulseSent = false;
  bool _isHolding = false;

  final _ps = FlickerStore.instance;
  final _ds = DiaryStore.instance;

  // First contact who flickered today (for the received flicker message).
  ({String name, String timeLabel})? get _receivedPulse {
    for (final d in _ds.diaries) {
      final rec = _ps.receivedToday(d.id);
      if (rec != null) {
        return (name: d.displayName, timeLabel: rec.timeLabel);
      }
    }
    return null;
  }

  bool get _hasSentAny =>
      _ds.diaries.any((d) => _ps.hasMeFlickeredToday(d.id));

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )
      ..addListener(_onHoldTick)
      ..addStatusListener(_onHoldStatus);
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    _breatheCtrl.dispose();
    super.dispose();
  }

  void _onHoldTick() {
    // Haptic at 50% and 90%.
    if (_holdCtrl.value > 0.5 && _holdCtrl.value < 0.52) {
      HapticFeedback.lightImpact();
    }
    if (_holdCtrl.value > 0.9 && _holdCtrl.value < 0.92) {
      HapticFeedback.mediumImpact();
    }
    setState(() {});
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _completePulse();
    }
  }

  void _startHold() {
    if (_pulseSent || _hasSentAny) return;
    setState(() => _isHolding = true);
    _holdCtrl.forward(from: 0);
  }

  void _cancelHold() {
    if (!_isHolding) return;
    _holdCtrl.stop();
    _holdCtrl.reverse();
    setState(() => _isHolding = false);
  }

  void _completePulse() {
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 100),
        () => HapticFeedback.lightImpact());
    final ids = _ds.diaries.map((d) => d.id).toList();
    final names = _ds.diaries.map((d) => d.displayName).toList();
    if (ids.isNotEmpty) _ps.sendFlickerToMany(ids, names);
    if (mounted) setState(() { _pulseSent = true; _isHolding = false; });
  }

  @override
  Widget build(BuildContext context) {
    final hasContacts = _ds.diaries.isNotEmpty;
    final svc = MorningService.instance;
    final received = _receivedPulse;
    final showHoldButton = !_hasSentAny && !_pulseSent;

    return Container(
      // Full-height sheet with rounded top corners.
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          // Radial amber glow background
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 0.85,
                  colors: [
                    AppColors.ember.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Drag handle
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderSoft,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                if (!hasContacts) ...[
                  // ── No-contacts state ────────────────────────────────────
                  const SizedBox(height: 52),
                  Text(
                    'Good morning.',
                    style: AppTypography.title(size: 28)
                        .copyWith(fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Saanjh is quieter without the people you love.',
                      style: AppTypography.serifItalic(size: 17),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 44),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        context.push(AppRoutes.inviteRecipient);
                      },
                      child: Container(
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: AppColors.emberGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppShadows.emberGlow(
                              offset: const Offset(0, 10)),
                        ),
                        child: Center(
                          child: Text(
                            'Invite someone →',
                            style: AppTypography.button(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Later',
                      style: AppTypography.label(
                          size: 14, color: AppColors.textFaint),
                    ),
                  ),
                  const Spacer(),
                ] else ...[
                  // ── Existing hold-to-pulse content ───────────────────────
                  const SizedBox(height: 32),

                  // Current time
                  Text(
                    svc.currentTimeLabel,
                    style: AppTypography.display(size: 48),
                  ),
                  const SizedBox(height: 12),

                  // Greeting
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      svc.morningGreeting,
                      style: AppTypography.serifItalic(size: 18),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Received pulse message
                  if (received != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(40, 0, 40, 28),
                      child: Text(
                        '${received.name} was here at ${received.timeLabel}. 💛',
                        style: AppTypography.serifItalic(
                          size: 18,
                          color: AppColors.emberWarm,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // Hold button — shown if pulse not yet sent
                  if (showHoldButton) ...[
                    _MiniHoldButton(
                      holdCtrl: _holdCtrl,
                      breatheCtrl: _breatheCtrl,
                      isHolding: _isHolding,
                      onPanDown: _startHold,
                      onPanUp: _cancelHold,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      received != null
                          ? 'Hold to say you\'re here too'
                          : 'Hold to say you\'re here',
                      style: AppTypography.label(
                          size: 13, color: AppColors.textFaint),
                    ),
                  ],

                  // Pulse sent confirmation
                  if (_pulseSent)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          const Text('💛',
                              style: TextStyle(fontSize: 32)),
                          const SizedBox(height: 8),
                          Text(
                            'You\'re here. They\'ll know.',
                            style: AppTypography.serifItalic(
                              size: 16,
                              color: AppColors.emberWarm,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Already sent (session state, not _pulseSent)
                  if (!showHoldButton && !_pulseSent && received == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'You\'ve flickered today 💛',
                        style: AppTypography.serifItalic(
                            size: 16, color: AppColors.textMuted),
                      ),
                    ),

                  const Spacer(),

                  // "Today I'm feeling..." row
                  _FeelingRow(
                    onTap: () {
                      Navigator.pop(context);
                      context.push(AppRoutes.voiceRecord, extra: {
                        'isVideo': false,
                        'isPrivateReflection': true,
                      });
                    },
                  ),

                  const SizedBox(height: 16),

                  // Continue button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Continue to diaries →',
                        style: AppTypography.label(
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mini hold button (80px) ──────────────────────────────────────────────────

class _MiniHoldButton extends StatelessWidget {
  final AnimationController holdCtrl;
  final AnimationController breatheCtrl;
  final bool isHolding;
  final VoidCallback onPanDown;
  final VoidCallback onPanUp;

  static const _r = 40.0; // 80px diameter

  const _MiniHoldButton({
    required this.holdCtrl,
    required this.breatheCtrl,
    required this.isHolding,
    required this.onPanDown,
    required this.onPanUp,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (_) => onPanDown(),
      onPanEnd: (_) => onPanUp(),
      onPanCancel: onPanUp,
      child: AnimatedBuilder(
        animation: Listenable.merge([holdCtrl, breatheCtrl]),
        builder: (_, _) {
          final breathScale =
              isHolding ? 1.0 : 1.0 + 0.03 * breatheCtrl.value;
          return Transform.scale(
            scale: breathScale,
            child: SizedBox(
              width: _r * 2 + 40,
              height: _r * 2 + 40,
              child: CustomPaint(
                painter: _MiniHoldPainter(
                  progress: holdCtrl.value,
                  isHolding: isHolding,
                  breathe: breatheCtrl.value,
                ),
                child: Center(
                  child: Container(
                    width: _r * 2,
                    height: _r * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.ember.withValues(alpha: 0.15),
                      border: Border.all(
                        color: AppColors.emberWarm.withValues(
                          alpha: isHolding ? 0.7 : 0.4,
                        ),
                        width: isHolding ? 1.5 : 1.0,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.favorite_rounded,
                        color: AppColors.emberWarm.withValues(
                          alpha: isHolding
                              ? 0.8 + holdCtrl.value * 0.2
                              : 0.5,
                        ),
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MiniHoldPainter extends CustomPainter {
  final double progress;
  final bool isHolding;
  final double breathe;

  const _MiniHoldPainter({
    required this.progress,
    required this.isHolding,
    required this.breathe,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isHolding || progress <= 0) return;
    final centre = Offset(size.width / 2, size.height / 2);
    const r = _MiniHoldButton._r + 6.0;

    // Progress arc
    final arcPaint = Paint()
      ..color = AppColors.emberWarm
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );

    // Glow at arc tip
    if (progress > 0.05) {
      final angle = -math.pi / 2 + 2 * math.pi * progress;
      final tipX = centre.dx + r * math.cos(angle);
      final tipY = centre.dy + r * math.sin(angle);
      canvas.drawCircle(
        Offset(tipX, tipY),
        3,
        Paint()..color = AppColors.emberWarm.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_MiniHoldPainter old) =>
      old.progress != progress || old.isHolding != isHolding;
}

// ─── "Today I'm feeling..." row ───────────────────────────────────────────────

class _FeelingRow extends StatelessWidget {
  final VoidCallback onTap;
  const _FeelingRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Row(
            children: [
              Icon(Icons.mic_rounded,
                  color: AppColors.textFaint, size: 18),
              const SizedBox(width: 12),
              Text(
                'Today I\'m feeling...',
                style: AppTypography.serifItalic(
                  size: 15,
                  color: AppColors.textFaint,
                ),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: AppColors.textFaint, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}

