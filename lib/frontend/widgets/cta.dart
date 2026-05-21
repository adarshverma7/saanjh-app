import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';

class CtaPrimary extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const CtaPrimary({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  State<CtaPrimary> createState() => _CtaPrimaryState();
}

class _CtaPrimaryState extends State<CtaPrimary> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.loading;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: disabled
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onPressed?.call();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: AppMotion.easeOut,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: AppColors.emberGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.ember.withValues(alpha: _pressed ? 0.32 : 0.42),
                blurRadius: 36,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 1,
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.20),
                  ),
                ),
                Center(
                  child: widget.loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text(
                          widget.label,
                          style: AppTypography.button(color: Colors.white),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CtaGhost extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;

  const CtaGhost({super.key, required this.label, this.onPressed});

  @override
  State<CtaGhost> createState() => _CtaGhostState();
}

class _CtaGhostState extends State<CtaGhost> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onPressed?.call();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: AppMotion.easeOut,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _pressed ? AppColors.surfaceTint : Colors.transparent,
            border: Border.all(
              color: _pressed ? AppColors.borderStrong : AppColors.borderSoft,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: AppTypography.button(
                color: Colors.white.withValues(alpha: _pressed ? 0.92 : 0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
