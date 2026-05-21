import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Off-screen rendered 400×400 voice moment card for social sharing.
/// Wrap in Offstage with a GlobalKey, then capture via ShareCardService.
class VoiceShareCard extends StatelessWidget {
  final String contactName;
  final String duration; // "0:18"
  final DateTime createdAt;
  final int seed; // drives deterministic waveform bars

  const VoiceShareCard({
    super.key,
    required this.contactName,
    required this.duration,
    required this.createdAt,
    required this.seed,
  });

  static const _months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _dateLabel =>
      '${_months[createdAt.month]} ${createdAt.day}, ${createdAt.year}';

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 400,
        height: 400,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2A0E00),
                Color(0xFF1A0800),
                Color(0xFF0A0400),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Ambient ember glow
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.2),
                      radius: 0.90,
                      colors: [
                        AppColors.ember.withValues(alpha: 0.14),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Card content
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 36, vertical: 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // "[Name]'s voice"
                    Text(
                      "$contactName's voice",
                      style: AppTypography.serifItalic(size: 18)
                          .copyWith(color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(),

                    // Waveform
                    SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _WaveformPainter(seed: seed),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Duration
                    Text(
                      duration.isNotEmpty ? duration : '0:00',
                      style: AppTypography.display(size: 28)
                          .copyWith(color: AppColors.emberWarm),
                    ),

                    const SizedBox(height: 6),

                    // Date
                    Text(
                      _dateLabel,
                      style: AppTypography.label(
                          size: 13, color: AppColors.textFaint),
                    ),

                    const Spacer(),

                    // Watermark — curiosity only, no CTA
                    Text(
                      'Saanjh · saanjh.app',
                      style: AppTypography.caption(size: 11.5).copyWith(
                        color: AppColors.textFaint.withValues(alpha: 0.55),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Waveform painter (seed-deterministic, same visual language as bubbles) ───

class _WaveformPainter extends CustomPainter {
  final int seed;
  static const _barCount = 36;

  const _WaveformPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    const barW = 5.0;
    const gap = 3.0;
    const totalW = _barCount * (barW + gap) - gap;
    double x = (size.width - totalW) / 2;
    final cy = size.height / 2;

    for (int i = 0; i < _barCount; i++) {
      final h = (0.15 + rng.nextDouble() * 0.85) * size.height;
      final alpha = 0.30 + rng.nextDouble() * 0.50;
      canvas.drawLine(
        Offset(x + barW / 2, cy - h / 2),
        Offset(x + barW / 2, cy + h / 2),
        Paint()
          ..color = AppColors.emberWarm.withValues(alpha: alpha)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = barW,
      );
      x += barW + gap;
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.seed != seed;
}
