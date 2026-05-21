import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

class GlowBackground extends StatefulWidget {
  final double glowTopFraction;
  final double glowSize;

  const GlowBackground({
    super.key,
    this.glowTopFraction = 0.18,
    this.glowSize = 360,
  });

  @override
  State<GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<GlowBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: AppMotion.breatheSlow)
        ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _ctrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
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
                  center: const Alignment(0, -0.45),
                  radius: 0.95,
                  colors: [
                    AppColors.ember.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.65],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final topInset = constraints.maxHeight * widget.glowTopFraction;
                return Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: topInset),
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _ctrl,
                        builder: (_, _) {
                          final t = Curves.easeInOut.transform(_ctrl.value);
                          final opacity = 0.85 + 0.15 * t;
                          final scale = 1.0 + 0.06 * t;
                          return Opacity(
                            opacity: opacity,
                            child: Transform.scale(
                              scale: scale,
                              child: SizedBox(
                                width: widget.glowSize,
                                height: widget.glowSize,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        AppColors.ember.withValues(alpha: 0.22),
                                        AppColors.ember.withValues(alpha: 0.16),
                                        AppColors.ember.withValues(alpha: 0.10),
                                        AppColors.emberWarm
                                            .withValues(alpha: 0.05),
                                        AppColors.emberWarm
                                            .withValues(alpha: 0.02),
                                        Colors.transparent,
                                      ],
                                      stops: const [
                                        0.0,
                                        0.18,
                                        0.34,
                                        0.50,
                                        0.68,
                                        0.88,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
