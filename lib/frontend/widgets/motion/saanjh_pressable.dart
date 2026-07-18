import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_motion.dart';

/// Haptic flavour fired on tap. Kept as an enum so call sites read cleanly.
enum SaanjhHaptic { none, light, selection, medium, heavy }

/// A universal press wrapper that gives any child a satisfying, CRED-grade
/// squish: a fast scale-down on press, then a springy overshoot back on release,
/// with an optional haptic. Use it around cards, tiles, icon buttons, list rows —
/// anything tappable — for a consistent, premium tactile feel.
///
/// Cheap to use everywhere: no AnimationController, just two implicitly-animated
/// values whose duration/curve flip with the press state (fast easeOut down,
/// springy settle up).
class SaanjhPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale at full press. 1.0 = none, lower = deeper squish. 0.955 reads as
  /// "premium button"; use ~0.97 for large cards so the motion stays subtle.
  final double pressedScale;

  /// Dim the child slightly while pressed — adds depth on flat surfaces.
  final bool dimOnPress;

  final SaanjhHaptic haptic;

  const SaanjhPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.955,
    this.dimOnPress = false,
    this.haptic = SaanjhHaptic.light,
  });

  @override
  State<SaanjhPressable> createState() => _SaanjhPressableState();
}

class _SaanjhPressableState extends State<SaanjhPressable> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool v) {
    if (!_enabled || _pressed == v) return;
    setState(() => _pressed = v);
  }

  void _fireHaptic() {
    switch (widget.haptic) {
      case SaanjhHaptic.none:
        break;
      case SaanjhHaptic.light:
        HapticFeedback.lightImpact();
      case SaanjhHaptic.selection:
        HapticFeedback.selectionClick();
      case SaanjhHaptic.medium:
        HapticFeedback.mediumImpact();
      case SaanjhHaptic.heavy:
        HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              _fireHaptic();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _fireHaptic();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        // Fast squish down, springy settle back up.
        duration: _pressed
            ? const Duration(milliseconds: 110)
            : const Duration(milliseconds: 340),
        curve: _pressed ? Curves.easeOut : AppMotion.easeSpring,
        child: widget.dimOnPress
            ? AnimatedOpacity(
                opacity: _pressed ? 0.86 : 1.0,
                duration: const Duration(milliseconds: 140),
                child: widget.child,
              )
            : widget.child,
      ),
    );
  }
}
