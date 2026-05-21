import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';

class _Slide {
  final String eyebrow;
  final String heading;
  final String headingItalic;
  final String sub;
  final Color glowColor;
  final Widget illustration;

  const _Slide({
    required this.eyebrow,
    required this.heading,
    required this.headingItalic,
    required this.sub,
    required this.glowColor,
    required this.illustration,
  });
}

class OnboardingIntroScreen extends StatefulWidget {
  const OnboardingIntroScreen({super.key});

  @override
  State<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
}

class _OnboardingIntroScreenState extends State<OnboardingIntroScreen>
    with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _page = 0;
  late final AnimationController _glowCtrl;
  late final AnimationController _contentCtrl;

  static final _slides = [
    _Slide(
      eyebrow: 'STAY CLOSE',
      heading: 'Say it.\nDon\'t ',
      headingItalic: 'type it.',
      sub: 'A 20-second voice note carries more love than any text message ever will.',
      glowColor: AppColors.ember,
      illustration: const _MicIllustration(),
    ),
    _Slide(
      eyebrow: 'ALWAYS THERE',
      heading: 'Your people,\nnever ',
      headingItalic: 'far away.',
      sub: 'An async diary between you and the ones who matter. No missed calls. No guilt. Just presence.',
      glowColor: AppColors.violet,
      illustration: const _ConnectionIllustration(),
    ),
    _Slide(
      eyebrow: 'FREE FOREVER',
      heading: 'Yours,\n',
      headingItalic: 'forever.',
      sub: 'Free to use. Always. Your memories can also live as a beautiful printed book — when you\'re ready.',
      glowColor: AppColors.successGreen,
      illustration: const _FreeIllustration(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _contentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _glowCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    HapticFeedback.selectionClick();
    if (_page < _slides.length - 1) {
      await _contentCtrl.reverse();
      await _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: AppMotion.easeOut,
      );
      setState(() => _page++);
      _contentCtrl.forward();
    } else {
      _goToSignup();
    }
  }

  void _goToSignup() {
    HapticFeedback.lightImpact();
    context.push(AppRoutes.phoneNumber);
  }

  void _skip() {
    HapticFeedback.selectionClick();
    _goToSignup();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_page];
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          // Animated glow background that changes colour per slide
          AnimatedBuilder(
            animation: _glowCtrl,
            builder: (_, w) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: AppMotion.easeOut,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.3),
                    radius: 1.2,
                    colors: [
                      slide.glowColor.withValues(
                          alpha: 0.18 + 0.06 * _glowCtrl.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),

          // Bottom gradient fade
          Positioned(
            left: 0, right: 0, bottom: 0,
            height: size.height * 0.45,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppColors.inkDeep],
                  stops: const [0.0, 0.8],
                ),
              ),
            ),
          ),

          // Page content
          PageView.builder(
            controller: _pageCtrl,
            physics: const ClampingScrollPhysics(),
            onPageChanged: (i) {
              setState(() => _page = i);
              _contentCtrl.forward(from: 0);
            },
            itemCount: _slides.length,
            itemBuilder: (_, i) => _SlideBody(
              slide: _slides[i],
              ctrl: _contentCtrl,
              isCurrent: i == _page,
            ),
          ),

          // Skip button
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            right: 20,
            child: AnimatedOpacity(
              opacity: _page < _slides.length - 1 ? 1.0 : 0.0,
              duration: AppMotion.fast,
              child: GestureDetector(
                onTap: _skip,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10), width: 1),
                  ),
                  child: Text('Skip',
                      style: AppTypography.label(
                          size: 13, color: AppColors.textMuted)),
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            left: 0, right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 24,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dot indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      final active = i == _page;
                      return AnimatedContainer(
                        duration: AppMotion.medium,
                        curve: AppMotion.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 28 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: active
                              ? slide.glowColor
                              : Colors.white.withValues(alpha: 0.18),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color:
                                        slide.glowColor.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  )
                                ]
                              : null,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  // CTA button
                  _NextButton(
                    label: _page == _slides.length - 1
                        ? 'Get started  →'
                        : 'Next  →',
                    color: slide.glowColor,
                    onTap: _next,
                  ),

                  const SizedBox(height: 14),
                  if (_page == _slides.length - 1)
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.invite),
                      child: Text(
                        'I received an invite →',
                        style: AppTypography.label(
                            size: 13, color: AppColors.textFaint),
                      ),
                    )
                  else
                    Text(
                      'Swipe to continue',
                      style: AppTypography.label(
                          size: 12, color: AppColors.textFaint),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Slide body ───────────────────────────────────────────────────────────────

class _SlideBody extends StatelessWidget {
  final _Slide slide;
  final AnimationController ctrl;
  final bool isCurrent;

  const _SlideBody({
    required this.slide,
    required this.ctrl,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 60),
          // Illustration
          SizedBox(
            height: size.height * 0.34,
            child: Center(child: slide.illustration),
          ),
          const SizedBox(height: 32),
          // Text content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: AnimatedBuilder(
              animation: ctrl,
              builder: (_, _) {
                // Each element enters with a staggered Interval so they
                // cascade in rather than appearing as a single block.
                // eyebrow: 0.00–0.55 · heading: 0.18–0.72 · sub: 0.35–1.00
                Widget staggered(Widget child, double start, double end) {
                  final raw = ((ctrl.value - start) / (end - start))
                      .clamp(0.0, 1.0);
                  final t = Curves.easeOutCubic.transform(raw);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - t)),
                      child: child,
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    staggered(
                      Text(slide.eyebrow,
                          style: AppTypography.eyebrow(
                              size: 11, color: slide.glowColor)),
                      0.00, 0.55,
                    ),
                    const SizedBox(height: 14),
                    staggered(
                      Text.rich(
                        TextSpan(
                          style: AppTypography.display(size: 40)
                              .copyWith(height: 1.08),
                          children: [
                            TextSpan(text: slide.heading),
                            TextSpan(
                              text: slide.headingItalic,
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: slide.glowColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      0.18, 0.72,
                    ),
                    const SizedBox(height: 16),
                    staggered(
                      Text(slide.sub,
                          style: AppTypography.serifItalic(
                              size: 17, color: AppColors.textMuted)),
                      0.35, 1.00,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Next button ──────────────────────────────────────────────────────────────

class _NextButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NextButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_NextButton> createState() => _NextButtonState();
}

class _NextButtonState extends State<_NextButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: AppMotion.fast,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _pressed ? 0.3 : 0.45),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5],
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(widget.label,
                    style: AppTypography.button(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Illustrations ────────────────────────────────────────────────────────────

class _MicIllustration extends StatefulWidget {
  const _MicIllustration();

  @override
  State<_MicIllustration> createState() => _MicIllustrationState();
}

class _MicIllustrationState extends State<_MicIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer ring
            Transform.scale(
              scale: 1.0 + 0.12 * t,
              child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.ember.withValues(alpha: 0.06 + 0.04 * t),
                ),
              ),
            ),
            // Middle ring
            Transform.scale(
              scale: 1.0 + 0.07 * t,
              child: Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.ember.withValues(alpha: 0.10 + 0.05 * t),
                ),
              ),
            ),
            // Core button
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.emberGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ember.withValues(alpha: 0.5 + 0.15 * t),
                    blurRadius: 40 + 10 * t,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.mic_rounded,
                  size: 44, color: Colors.white),
            ),
            // Waveform bars around
            Positioned.fill(
              child: CustomPaint(
                painter: _WaveBars(t: t),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WaveBars extends CustomPainter {
  final double t;
  _WaveBars({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()
      ..color = AppColors.emberWarm.withValues(alpha: 0.5)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const count = 5;
    final rng = math.Random(7);
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi;
      final base = 65.0;
      final h = 8.0 + 12.0 * rng.nextDouble() + 6.0 * math.sin(t * math.pi + i);
      final r1 = base;
      final r2 = base + h;
      canvas.drawLine(
        Offset(cx + r1 * math.cos(angle), cy + r1 * math.sin(angle)),
        Offset(cx + r2 * math.cos(angle), cy + r2 * math.sin(angle)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveBars o) => o.t != t;
}

// ─── Slide 2 — Connection ─────────────────────────────────────────────────────

class _ConnectionIllustration extends StatefulWidget {
  const _ConnectionIllustration();

  @override
  State<_ConnectionIllustration> createState() => _ConnectionIllustrationState();
}

class _ConnectionIllustrationState extends State<_ConnectionIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, w) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return SizedBox(
          width: 220, height: 200,
          child: CustomPaint(painter: _ConnectionPainter(t: t)),
        );
      },
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  final double t;
  _ConnectionPainter({required this.t});

  static const _purple = AppColors.violet;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Centre node (you)
    _drawNode(canvas, Offset(cx, cy), 28, _purple, 0.9 + 0.1 * t);

    // Surrounding family nodes
    final positions = [
      (cx - 80.0, cy - 50.0, AppColors.ember, 'P'),
      (cx + 80.0, cy - 50.0, Color(0xFFFF6B8A), 'M'),
      (cx, cy + 80.0, AppColors.successGreen, 'K'),
    ];

    for (final (x, y, color, _) in positions) {
      // Animated connecting line
      final lineAlpha = 0.18 + 0.12 * t;
      final linePaint = Paint()
        ..color = color.withValues(alpha: lineAlpha)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(cx, cy), Offset(x, y), linePaint);

      // Pulse dot on line
      final pct = (t + _phase(x, y)) % 1.0;
      final px = cx + (x - cx) * pct;
      final py = cy + (y - cy) * pct;
      canvas.drawCircle(
        Offset(px, py), 3,
        Paint()..color = color.withValues(alpha: 0.9),
      );

      _drawNode(canvas, Offset(x, y), 20, color, 0.8 + 0.12 * t);
    }
  }

  double _phase(double x, double y) => ((x + y) % 100) / 100;

  void _drawNode(Canvas canvas, Offset c, double r, Color color, double glow) {
    canvas.drawCircle(
      c, r * 1.6,
      Paint()..color = color.withValues(alpha: 0.12 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      c, r,
      Paint()
        ..shader = LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c, r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ConnectionPainter o) => o.t != t;
}

// ─── Slide 3 — Free ──────────────────────────────────────────────────────────

class _FreeIllustration extends StatefulWidget {
  const _FreeIllustration();

  @override
  State<_FreeIllustration> createState() => _FreeIllustrationState();
}

class _FreeIllustrationState extends State<_FreeIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, w) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow
            Transform.scale(
              scale: 1.0 + 0.08 * t,
              child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.successGreen.withValues(alpha: 0.06 + 0.04 * t),
                ),
              ),
            ),
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.successGreen.withValues(alpha: 0.15),
                border: Border.all(
                    color: AppColors.successGreen.withValues(alpha: 0.4),
                    width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.successGreen.withValues(alpha: 0.3 + 0.15 * t),
                    blurRadius: 30 + 10 * t,
                  ),
                ],
              ),
              child: const Icon(Icons.favorite_rounded,
                  size: 44, color: AppColors.successGreen),
            ),
            // Floating badges
            ..._badges(t),
          ],
        );
      },
    );
  }

  List<Widget> _badges(double t) {
    final items = [
      (-90.0, -40.0, 'No ads', 0.0),
      (85.0, -50.0, 'No fees', 0.33),
      (-70.0, 60.0, 'Always free', 0.66),
    ];
    return items.map((item) {
      final (dx, dy, label, phase) = item;
      final anim = Curves.easeInOut.transform((t + phase) % 1.0);
      return Transform.translate(
        offset: Offset(dx, dy + 4 * math.sin(anim * math.pi)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.successGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.successGreen.withValues(alpha: 0.35), width: 1),
          ),
          child: Text(label,
              style: AppTypography.label(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: const Color(0xFF7CD992))),
        ),
      );
    }).toList();
  }
}
