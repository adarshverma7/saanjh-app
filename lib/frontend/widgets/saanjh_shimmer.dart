import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';

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
      highlightColor: AppColors.ink,
      child: child,
    );
  }
}
