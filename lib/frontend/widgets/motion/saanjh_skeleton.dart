import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Warm shimmer skeletons. Loading states shouldn't feel like dead air — these
/// pulse with a faint ember-tinted sweep so a loading screen reads as part of
/// the experience, not a stall.
///
/// Wrap a group of [SkeletonBox]/[SkeletonLine]/[SkeletonCircle] shapes in a
/// [SaanjhSkeleton] to drive them from one shimmer controller (cheap even with
/// many shapes).

class SaanjhSkeleton extends StatelessWidget {
  final Widget child;
  const SaanjhSkeleton({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.inkRaised,
      // A warm, dark ember-brown highlight — reads as a soft dusk sweep.
      highlightColor: const Color(0xFF2A1712),
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.inkRaised,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  const SkeletonLine({super.key, this.width, this.height = 12});

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: width, height: height, radius: height / 2);
}

class SkeletonCircle extends StatelessWidget {
  final double size;
  const SkeletonCircle({super.key, required this.size});

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: size, height: size, radius: size / 2);
}

/// A ready-made skeleton for a diary/connection list row (avatar + two lines).
class DiaryCardSkeleton extends StatelessWidget {
  const DiaryCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.m,
      ),
      child: Row(
        children: [
          const SkeletonCircle(size: 56),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonLine(width: 140, height: 14),
                SizedBox(height: AppSpacing.s),
                SkeletonLine(width: 220, height: 11),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.l),
          const SkeletonLine(width: 34, height: 10),
        ],
      ),
    );
  }
}

/// A list of [DiaryCardSkeleton]s under one shimmer — drop-in for the diary list
/// loading state.
class DiaryListSkeleton extends StatelessWidget {
  final int count;
  const DiaryListSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return SaanjhSkeleton(
      child: Column(
        children: List.generate(
          count,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.s),
            child: DiaryCardSkeleton(),
          ),
        ),
      ),
    );
  }
}

/// A chat-thread loading state: alternating incoming/outgoing bubble blanks.
class ThreadSkeleton extends StatelessWidget {
  final int count;
  const ThreadSkeleton({super.key, this.count = 7});

  @override
  Widget build(BuildContext context) {
    return SaanjhSkeleton(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          children: List.generate(count, (i) {
            final mine = i.isOdd;
            final w = 140.0 + (i * 37) % 120;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.l),
              child: Align(
                alignment:
                    mine ? Alignment.centerRight : Alignment.centerLeft,
                child: SkeletonBox(width: w, height: 44, radius: 18),
              ),
            );
          }),
        ),
      ),
    );
  }
}
