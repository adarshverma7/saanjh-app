import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import '../state/flicker_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Full-screen emotional overlay shown when the recipient receives a Flicker.
///
/// Shown via [FlickerReceivedOverlay.show] from HomeScreen whenever
/// [FlickerStore.onFlickerReceived] fires. Displays only once per Flicker
/// per day (guarded in FlickerStore with SharedPreferences).
class FlickerReceivedOverlay extends StatefulWidget {
  final String senderName;
  final String senderInitial;
  final Color avatarColor;
  final VoidCallback onSendBack;

  const FlickerReceivedOverlay({
    super.key,
    required this.senderName,
    required this.senderInitial,
    required this.avatarColor,
    required this.onSendBack,
  });

  static Future<void> show(
    BuildContext context, {
    required FlickerRecord record,
    required Color avatarColor,
    required String senderInitial,
    required VoidCallback onSendBack,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.90),
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (ctx, anim1, anim2) => FlickerReceivedOverlay(
        senderName: record.personName,
        senderInitial: senderInitial,
        avatarColor: avatarColor,
        onSendBack: onSendBack,
      ),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final scale = Tween<double>(begin: 0.86, end: 1.0).animate(
          CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
        );
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: ScaleTransition(scale: scale, child: child),
        );
      },
    );
  }

  @override
  State<FlickerReceivedOverlay> createState() =>
      _FlickerReceivedOverlayState();
}

class _FlickerReceivedOverlayState extends State<FlickerReceivedOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _emberCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _textCtrl;

  @override
  void initState() {
    super.initState();

    _emberCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _playHaptics();
  }

  Future<void> _playHaptics() async {
    // Lub-dub heartbeat — mirrors the flicker send ritual.
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 130));
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 320));

    final hasVibrator = await Vibration.hasVibrator();
    if (!mounted) return;
    if (hasVibrator) {
      Vibration.vibrate(pattern: [0, 80, 70, 100], repeat: -1);
      await Future.delayed(const Duration(milliseconds: 900));
      Vibration.cancel();
    } else {
      await HapticFeedback.selectionClick();
    }
  }

  @override
  void dispose() {
    _emberCtrl.dispose();
    _pulseCtrl.dispose();
    _textCtrl.dispose();
    Vibration.cancel();
    super.dispose();
  }

  void _handleSendBack() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
    widget.onSendBack();
  }

  void _handleDismiss() {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── Floating ember particles ──────────────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _emberCtrl,
              builder: (_, _) => CustomPaint(
                painter: _FloatingEmbersPainter(t: _emberCtrl.value),
              ),
            ),
          ),

          // ── Ambient radial warmth at centre ──────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, _) {
                final alpha = 0.04 + _pulseCtrl.value * 0.06;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.10),
                      radius: 0.80,
                      colors: [
                        AppColors.ember.withValues(alpha: alpha),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Central content ───────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),

                // Avatar with glow rings
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, _) => _GlowingAvatar(
                    initial: widget.senderInitial,
                    color: widget.avatarColor,
                    pulse: _pulseCtrl.value,
                  ),
                ),

                const SizedBox(height: 36),

                // Main message — staggered fade in
                AnimatedBuilder(
                  animation: _textCtrl,
                  builder: (_, _) {
                    final t = _textCtrl.value;
                    final nameOpacity = (t / 0.45).clamp(0.0, 1.0);
                    final bodyOpacity =
                        ((t - 0.30) / 0.45).clamp(0.0, 1.0);
                    final bodySlide = 10 * (1 - bodyOpacity);
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        children: [
                          // "[Name]"
                          Opacity(
                            opacity: nameOpacity,
                            child: Text(
                              widget.senderName,
                              style: AppTypography.title(
                                size: 36,
                                weight: FontWeight.w700,
                              ).copyWith(
                                color: AppColors.emberBright,
                                fontStyle: FontStyle.italic,
                                letterSpacing: -0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // "sent you a Flicker ✨"
                          Opacity(
                            opacity: bodyOpacity,
                            child: Transform.translate(
                              offset: Offset(0, bodySlide),
                              child: Text(
                                'sent you a Flicker ✨',
                                style: AppTypography.title(
                                  size: 26,
                                  weight: FontWeight.w500,
                                ).copyWith(
                                  color: Colors.white
                                      .withValues(alpha: 0.90),
                                  height: 1.25,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Opacity(
                            opacity: bodyOpacity,
                            child: Transform.translate(
                              offset: Offset(0, bodySlide * 1.4),
                              child: Text(
                                'They\'re thinking of you right now.',
                                style: AppTypography.serifItalic(
                                  size: 16,
                                  color: Colors.white
                                      .withValues(alpha: 0.42),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const Spacer(flex: 2),

                // CTAs
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _handleSendBack,
                        child: Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: AppColors.emberGradient,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.ember
                                    .withValues(alpha: 0.55),
                                blurRadius: 36,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'Send one back  💛',
                              style: AppTypography.button(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: _handleDismiss,
                        child: Text(
                          'Maybe later',
                          style: AppTypography.label(
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.30),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Glowing avatar ───────────────────────────────────────────────────────────

class _GlowingAvatar extends StatelessWidget {
  final String initial;
  final Color color;
  final double pulse; // 0.0 → 1.0

  const _GlowingAvatar({
    required this.initial,
    required this.color,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final glowAlpha = 0.22 + pulse * 0.14;
    final ringAlpha = 0.20 + pulse * 0.30;
    final outerRingR = 52.0 + pulse * 10;

    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer diffuse glow
          Container(
            width: outerRingR * 2,
            height: outerRingR * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.ember.withValues(alpha: glowAlpha),
                  blurRadius: 40 + pulse * 20,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),

          // Outer ring (breathing)
          Container(
            width: outerRingR * 2,
            height: outerRingR * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.emberWarm.withValues(alpha: ringAlpha * 0.5),
                width: 1,
              ),
            ),
          ),

          // Inner ring
          Container(
            width: 106,
            height: 106,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.emberWarm.withValues(alpha: ringAlpha),
                width: 1.5,
              ),
            ),
          ),

          // Avatar
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.65)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: AppTypography.display(size: 40).copyWith(
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Floating embers painter ──────────────────────────────────────────────────

class _FloatingEmbersPainter extends CustomPainter {
  final double t; // 0.0 → 1.0, continuously repeating

  _FloatingEmbersPainter({required this.t});

  static final _rng = math.Random(73);
  static final _particles = List.generate(28, (i) {
    return _EmberParticle(
      x:          _rng.nextDouble(),
      phase:      _rng.nextDouble(),
      speed:      0.18 + _rng.nextDouble() * 0.22,
      size:       1.6 + _rng.nextDouble() * 3.8,
      sway:       (_rng.nextDouble() - 0.5) * 0.07,
      colorIndex: i % _colors.length,
    );
  });

  static const _colors = [
    Color(0xFFFF9500), // amber
    Color(0xFFFFCC60), // gold
    Color(0xFFFF6B00), // ember
    Color(0xFFFFE08A), // pale gold
    Color(0xFFFF8C40), // warm orange
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final progress = ((t * p.speed / 0.20 + p.phase) % 1.0);
      final x = size.width * p.x +
          math.sin(progress * 2 * math.pi * 0.7) * size.width * p.sway;
      final y = size.height * (1.05 - progress * 1.10);

      double alpha;
      if (progress < 0.12) {
        alpha = progress / 0.12;
      } else if (progress > 0.72) {
        alpha = (1.0 - progress) / 0.28;
      } else {
        alpha = 1.0;
      }

      canvas.drawCircle(
        Offset(x, y),
        p.size * (0.7 + progress * 0.3),
        Paint()
          ..color = _colors[p.colorIndex]
              .withValues(alpha: (alpha * 0.60).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_FloatingEmbersPainter o) => o.t != t;
}

class _EmberParticle {
  final double x;
  final double phase;
  final double speed;
  final double size;
  final double sway;
  final int colorIndex;

  const _EmberParticle({
    required this.x,
    required this.phase,
    required this.speed,
    required this.size,
    required this.sway,
    required this.colorIndex,
  });
}
