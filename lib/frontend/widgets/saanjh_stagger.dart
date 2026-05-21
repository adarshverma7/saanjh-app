import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Fades and slides a list item in after a staggered delay derived from
/// its [index] via [AppMotion.stagger].
///
/// Items with [index] > [AppMotion.stagger]'s maxIndex cap appear
/// immediately so that scrolling into long lists has no lag.
class SaanjhStaggerItem extends StatefulWidget {
  final int index;
  final Widget child;

  const SaanjhStaggerItem({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  State<SaanjhStaggerItem> createState() => _SaanjhStaggerItemState();
}

class _SaanjhStaggerItemState extends State<SaanjhStaggerItem> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final delay = AppMotion.stagger(widget.index);
    if (delay == Duration.zero) {
      _visible = true;
    } else {
      Future.delayed(delay, () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: AppMotion.slow,
      curve: AppMotion.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.03),
        duration: AppMotion.slow,
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}
