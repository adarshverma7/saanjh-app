import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// A crisp entrance animation: the child fades up from slightly below with a
/// touch of scale, on a single controller. Snappier than a long cross-fade —
/// this is the "content lands with intent" feel that makes lists and screens
/// read as premium.
///
/// Pass an increasing [delay] (or use [SaanjhReveal.staggered]) to cascade a
/// column of items. Honours the platform "reduce motion" setting by showing the
/// child immediately.
class SaanjhReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Vertical distance (logical px) the child rises from.
  final double offsetY;

  /// Starting scale. 1.0 disables the scale component.
  final double fromScale;

  const SaanjhReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.offsetY = 18,
    this.fromScale = 0.98,
  });

  /// Convenience for list items: delay grows with [index] but caps so long
  /// lists don't accumulate visible lag.
  factory SaanjhReveal.staggered({
    Key? key,
    required int index,
    required Widget child,
    int baseMs = 55,
    int maxIndex = 8,
    double offsetY = 18,
  }) {
    return SaanjhReveal(
      key: key,
      delay: Duration(milliseconds: baseMs * index.clamp(0, maxIndex)),
      offsetY: offsetY,
      child: child,
    );
  }

  @override
  State<SaanjhReveal> createState() => _SaanjhRevealState();
}

class _SaanjhRevealState extends State<SaanjhReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: AppMotion.easeOut);

  bool _reducedMotion = false;

  bool _kickedOff = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Run exactly once, on the first time dependencies (MediaQuery) resolve.
    if (_kickedOff) return;
    _kickedOff = true;

    // Reduce-motion: skip the animation and show the child fully.
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reducedMotion) {
      _c.value = 1.0;
    } else {
      _start();
    }
  }

  void _start() {
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reducedMotion) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final t = _t.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offsetY),
            child: Transform.scale(
              scale: widget.fromScale + (1 - widget.fromScale) * t,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
