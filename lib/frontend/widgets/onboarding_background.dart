import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class OnboardingBackground extends StatelessWidget {
  const OnboardingBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.inkRaised,
                    AppColors.ink,
                    AppColors.inkDeep,
                  ],
                  stops: [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.85),
                  radius: 0.9,
                  colors: [
                    Color(0x1AE8720C),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.65],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
