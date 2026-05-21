import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';

class SaanjhEmptyState extends StatefulWidget {
  final Widget? visual;
  final String title;
  final String? body;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const SaanjhEmptyState({
    super.key,
    this.visual,
    required this.title,
    this.body,
    this.ctaLabel,
    this.onCta,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  State<SaanjhEmptyState> createState() => _SaanjhEmptyStateState();
}

class _SaanjhEmptyStateState extends State<SaanjhEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.slow)
      ..forward();
    final curved = CurvedAnimation(parent: _ctrl, curve: AppMotion.easeOut);
    _fade = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(36, 0, 36, 80),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.visual != null) ...[
                  widget.visual!,
                  const SizedBox(height: 28),
                ],
                Text(
                  widget.title,
                  style: AppTypography.title(size: 22),
                  textAlign: TextAlign.center,
                ),
                if (widget.body != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.body!,
                    style: AppTypography.serifItalic(size: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (widget.ctaLabel != null && widget.onCta != null) ...[
                  const SizedBox(height: 36),
                  _CtaButton(label: widget.ctaLabel!, onTap: widget.onCta!),
                ],
                if (widget.secondaryLabel != null &&
                    widget.onSecondary != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.onSecondary,
                    child: Text(
                      widget.secondaryLabel!,
                      style: AppTypography.label(
                          size: 14, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Amber gradient CTA button ────────────────────────────────────────────────

class _CtaButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _CtaButton({required this.label, required this.onTap});

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: AppMotion.fast,
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: AppColors.emberGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.emberGlow(offset: const Offset(0, 12)),
          ),
          child: Center(
            child: Text(widget.label,
                style: AppTypography.button(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
