import 'package:flutter/material.dart';

import 'motion/saanjh_reveal.dart';

/// Fades and rises a list item in after a staggered, index-derived delay.
///
/// Kept as the app-wide stagger entry point (many screens use it); it now
/// delegates to [SaanjhReveal] so every list gets the crisper fade-up-with-scale
/// entrance and reduced-motion handling for free.
class SaanjhStaggerItem extends StatelessWidget {
  final int index;
  final Widget child;

  const SaanjhStaggerItem({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) =>
      SaanjhReveal.staggered(index: index, child: child);
}
