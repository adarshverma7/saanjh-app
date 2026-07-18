import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// A number that smoothly rolls from its previous value to a new one whenever
/// [value] changes — the little flourish that makes streaks and stats feel
/// alive instead of just snapping.
class SaanjhCount extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final Duration duration;

  const SaanjhCount({
    super.key,
    required this.value,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.duration = const Duration(milliseconds: 720),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: AppMotion.easeOut,
      builder: (context, v, _) => Text(
        '$prefix${v.round()}$suffix',
        style: style,
      ),
    );
  }
}
