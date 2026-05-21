import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

class SaanjhLogo extends StatefulWidget {
  final double size;
  const SaanjhLogo({super.key, this.size = 124});

  @override
  State<SaanjhLogo> createState() => _SaanjhLogoState();
}

class _SaanjhLogoState extends State<SaanjhLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: AppMotion.breatheLogo)
        ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.size * 0.258;
    final br = BorderRadius.circular(radius);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        final scale = 1.0 + 0.025 * t;
        final glowAlpha = 0.42 + 0.13 * t;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              borderRadius: br,
              boxShadow: [
                BoxShadow(
                  color: AppColors.ember.withValues(alpha: glowAlpha),
                  blurRadius: 80,
                  spreadRadius: 0,
                  offset: const Offset(0, 30),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: br,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-0.6, -0.8),
                          end: Alignment(0.6, 0.8),
                          colors: [
                            AppColors.emberWarm,
                            AppColors.ember,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.4, -0.5),
                          radius: 0.85,
                          colors: [
                            const Color(0xFFFFDCA0).withValues(alpha: 0.55),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.55],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -1.0),
                          radius: 0.95,
                          colors: [
                            Colors.white.withValues(alpha: 0.30),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.6],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.25),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 22,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.16),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: br,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: CustomPaint(
                      size: Size(widget.size * 0.53, widget.size * 0.53),
                      painter: _SunHorizonPainter(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SunHorizonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;

    final horizonRect = Rect.fromLTWH(6 * s, 44 * s, 52 * s, 4 * s);
    final horizonPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.4),
          Colors.white,
          Colors.white.withValues(alpha: 0.4),
        ],
      ).createShader(horizonRect)
      ..strokeWidth = 2.4 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(6 * s, 46 * s),
      Offset(58 * s, 46 * s),
      horizonPaint,
    );

    final sunCenter = Offset(32 * s, 34 * s);
    final sunRadius = 13 * s;
    final sunPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.95),
          const Color(0xFFFFE5C0).withValues(alpha: 0.85),
        ],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: sunRadius));
    canvas.drawCircle(sunCenter, sunRadius, sunPaint);

    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()..color = Colors.white.withValues(alpha: 0.15),
    );

    final rayStroke = Paint()
      ..strokeWidth = 2.4 * s
      ..strokeCap = StrokeCap.round;
    final rays = <(Offset, Offset, double)>[
      (const Offset(32, 14), const Offset(32, 20), 0.85),
      (const Offset(14, 22), const Offset(18, 26), 0.65),
      (const Offset(50, 22), const Offset(46, 26), 0.65),
      (const Offset(6, 34), const Offset(11, 34), 0.5),
      (const Offset(53, 34), const Offset(58, 34), 0.5),
    ];
    for (final (a, b, alpha) in rays) {
      rayStroke.color = Colors.white.withValues(alpha: alpha);
      canvas.drawLine(
        Offset(a.dx * s, a.dy * s),
        Offset(b.dx * s, b.dy * s),
        rayStroke,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
