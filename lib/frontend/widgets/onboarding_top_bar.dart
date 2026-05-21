import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';

class OnboardingTopBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onBack;

  const OnboardingTopBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Row(
        children: [
          _BackButton(onTap: onBack),
          const Spacer(),
          _ProgressDots(current: currentStep, total: totalSteps),
        ],
      ),
    );
  }
}

class _BackButton extends StatefulWidget {
  final VoidCallback? onTap;
  const _BackButton({required this.onTap});

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: AppMotion.easeOut,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Center(
            child: CustomPaint(
              size: const Size(16, 16),
              painter: _ChevronLeftPainter(
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChevronLeftPainter extends CustomPainter {
  final Color color;
  _ChevronLeftPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(10 * s, 12 * s)
      ..lineTo(6 * s, 8 * s)
      ..lineTo(10 * s, 4 * s);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChevronLeftPainter old) => old.color != color;
}

class _ProgressDots extends StatelessWidget {
  final int current;
  final int total;

  const _ProgressDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          _Dot(active: i <= current),
        ],
        const SizedBox(width: 10),
        Text(
          '$current of $total',
          style: AppTypography.eyebrow(size: 11)
              .copyWith(letterSpacing: 0.04 * 11),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: AppMotion.easeOut,
      width: 24,
      height: 3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: active
            ? AppColors.emberWarm
            : Colors.white.withValues(alpha: 0.12),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.emberWarm.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
    );
  }
}
