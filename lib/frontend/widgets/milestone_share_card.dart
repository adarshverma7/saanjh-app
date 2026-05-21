import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class MilestoneShareCard extends StatelessWidget {
  final int streakDays;
  final String contactName;
  final String milestoneLabel;

  const MilestoneShareCard({
    super.key,
    required this.streakDays,
    required this.contactName,
    required this.milestoneLabel,
  });

  String get _tree {
    if (streakDays >= 365) return '🌸✨';
    if (streakDays >= 90) return '🌸';
    if (streakDays >= 60) return '🎋';
    if (streakDays >= 30) return '🌲';
    return '🌿';
  }

  String get _firstName => contactName.split(' ').first;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 400,
        height: 700,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2A0E00), Color(0xFF0A0400)],
            ),
          ),
          child: Stack(
            children: [
              // Decorative faded waveform background
              Positioned.fill(
                child: CustomPaint(painter: _WaveformBgPainter()),
              ),

              // Main content
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),

                  // Tree emoji
                  Text(_tree, style: const TextStyle(fontSize: 80)),
                  const SizedBox(height: 24),

                  // Flame + streak number
                  Text(
                    '🔥 $streakDays',
                    style: AppTypography.display(size: 72).copyWith(
                      color: AppColors.emberWarm,
                      height: 1.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),

                  // Mornings with name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      '$streakDays mornings with $_firstName',
                      style: AppTypography.serifItalic(size: 24).copyWith(
                        color: Colors.white.withValues(alpha: 0.90),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Milestone label
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      milestoneLabel,
                      style: AppTypography.serifItalic(size: 18).copyWith(
                        color: AppColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const Spacer(),
                ],
              ),

              // Watermark at bottom
              Positioned(
                bottom: 28,
                left: 0,
                right: 0,
                child: Text(
                  'Saanjh · saanjh.app',
                  style: AppTypography.label(
                    size: 11,
                    color: AppColors.textFaint,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Decorative waveform background ──────────────────────────────────────────

class _WaveformBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..style = PaintingStyle.fill;

    const barCount = 42;
    final barW = size.width / barCount;
    for (int i = 0; i < barCount; i++) {
      final h = 32.0 + rng.nextDouble() * 110;
      final x = i * barW;
      final y = size.height / 2 - h / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, y, barW - 4, h),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformBgPainter old) => false;
}
