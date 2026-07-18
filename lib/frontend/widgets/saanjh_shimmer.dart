import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';

/// Wraps [child] in a warm dusk shimmer while [isLoading]. The highlight is a
/// soft ember-brown (not dark-on-dark), so loading placeholders actually read
/// as a gentle sweep of light rather than sitting flat and lifeless.
class SaanjhShimmer extends StatelessWidget {
  final Widget child;
  final bool isLoading;

  const SaanjhShimmer({
    super.key,
    required this.child,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return child;
    return Shimmer.fromColors(
      baseColor: AppColors.inkRaised,
      highlightColor: const Color(0xFF2A1712),
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}
