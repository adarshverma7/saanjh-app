import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'flicker_state.dart';

// ─── Ambient painter ──────────────────────────────────────────────────────────
// Premium approach: slow-breathing gradient blobs, NOT particles or flames.
// The warmth is *felt*, not seen. Like a room with a fireplace — you sense the
// glow, you don't watch the fire.

class _AmbientPainter extends CustomPainter {
  final FlickerWarmth warmth;
  final double t1;   // 0-1, primary bloom cycle (6 s)
  final double t2;   // 0-1, secondary bloom cycle (9 s, offset phase)
  final double t3;   // 0-1, bottom heat cycle (4 s)
  final double brightBoost; // 0-1 transient (on note play)

  _AmbientPainter({
    required this.warmth,
    required this.t1,
    required this.t2,
    required this.t3,
    required this.brightBoost,
  });

  // ── Colour look-up per warmth ─────────────────────────────────────────────

  Color get _bottomHeatColor => switch (warmth) {
        FlickerWarmth.fullBurn => const Color(0xFFE8720C),
        FlickerWarmth.embers   => const Color(0xFF7A1C00),
        FlickerWarmth.coldAsh  => const Color(0xFF1A2848),
      };

  double get _bottomHeatMax => switch (warmth) {
        FlickerWarmth.fullBurn => 0.20,
        FlickerWarmth.embers   => 0.13,
        FlickerWarmth.coldAsh  => 0.07,
      };

  Color get _bloomColor => switch (warmth) {
        FlickerWarmth.fullBurn => const Color(0xFFCC4400),
        FlickerWarmth.embers   => const Color(0xFF661100),
        FlickerWarmth.coldAsh  => const Color(0xFF0E1830),
      };

  double get _bloomMax => switch (warmth) {
        FlickerWarmth.fullBurn => 0.14,
        FlickerWarmth.embers   => 0.09,
        FlickerWarmth.coldAsh  => 0.05,
      };

  Color get _accentColor => switch (warmth) {
        FlickerWarmth.fullBurn => const Color(0xFFFF8800),
        FlickerWarmth.embers   => const Color(0xFF993300),
        FlickerWarmth.coldAsh  => const Color(0xFF0A1428),
      };

  List<Color> get _baseGradient => switch (warmth) {
        FlickerWarmth.fullBurn => const [Color(0xFF110806), Color(0xFF0A0506), Color(0xFF070305)],
        FlickerWarmth.embers   => const [Color(0xFF0D0605), Color(0xFF080403), Color(0xFF060303)],
        FlickerWarmth.coldAsh  => const [Color(0xFF070810), Color(0xFF050608), Color(0xFF040507)],
      };

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // ── 1. Base gradient (static warmth impression) ───────────────────────
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _baseGradient,
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Offset.zero & size),
    );

    // ── 2. Bottom ember heat (wide, blurred, pulsing) ─────────────────────
    // This is the "hearth mouth" — always at the bottom of the screen
    final bAlpha = _bottomHeatMax * (0.72 + 0.28 * t3) + brightBoost * 0.08;
    final bW = w * (1.10 + 0.08 * t3);
    final bH = h * (0.28 + 0.05 * t3);
    _drawBlob(
      canvas,
      center: Offset(cx, h + h * 0.04), // slightly below screen bottom
      rx: bW / 2,
      ry: bH / 2,
      color: _bottomHeatColor,
      alpha: bAlpha.clamp(0.0, 0.30),
      blur: 55,
    );

    // ── 3. Primary mid-screen bloom (breathes on t1) ──────────────────────
    final p1Alpha = _bloomMax * (0.75 + 0.25 * t1) + brightBoost * 0.05;
    final p1Y = h * (0.55 + 0.04 * t1); // drifts slightly upward
    _drawBlob(
      canvas,
      center: Offset(cx, p1Y),
      rx: w * (0.55 + 0.08 * t1),
      ry: h * (0.30 + 0.06 * t1),
      color: _bloomColor,
      alpha: p1Alpha.clamp(0.0, 0.18),
      blur: 70,
    );

    // ── 4. Secondary accent bloom (offset, slower drift on t2) ───────────
    // Gives the asymmetry that makes it feel organic, not digital
    final p2Alpha = _bloomMax * 0.6 * (0.6 + 0.4 * t2);
    final p2X = cx + w * 0.12 * math.sin(t2 * math.pi); // gentle left-right drift
    final p2Y = h * (0.40 + 0.08 * t2);
    _drawBlob(
      canvas,
      center: Offset(p2X, p2Y),
      rx: w * (0.35 + 0.05 * t2),
      ry: h * (0.22 + 0.04 * t2),
      color: _accentColor,
      alpha: p2Alpha.clamp(0.0, 0.10),
      blur: 80,
    );

    // ── 5. Bright boost overlay (on note play) ────────────────────────────
    if (brightBoost > 0.02) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = _bottomHeatColor.withValues(alpha: brightBoost * 0.07),
      );
    }
  }

  void _drawBlob(
    Canvas canvas, {
    required Offset center,
    required double rx,
    required double ry,
    required Color color,
    required double alpha,
    required double blur,
  }) {
    if (alpha <= 0.005) return;

    final rect = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.4),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  @override
  // Time values change every frame — always repaint.
  bool shouldRepaint(_AmbientPainter o) =>
      o.t1 != t1 || o.t2 != t2 || o.t3 != t3 ||
      o.brightBoost != brightBoost || o.warmth != warmth;
}

// ─── FlickerBackground ─────────────────────────────────────────────────────────

/// Wraps [child] in a living ambient warmth background.
///
/// Three independent animation loops run at different speeds so the pattern
/// never feels mechanical. The background is deliberately subtle — warmth is
/// *implied*, not performed.
class FlickerBackground extends StatefulWidget {
  final FlickerWarmth warmth;
  final Widget child;
  final FlickerController? controller;

  const FlickerBackground({
    super.key,
    required this.warmth,
    required this.child,
    this.controller,
  });

  @override
  State<FlickerBackground> createState() => _FlickerBackgroundState();
}

class _FlickerBackgroundState extends State<FlickerBackground>
    with TickerProviderStateMixin {
  // Three independent loops at prime-number-ish durations so they never
  // synchronise and create noticeable repetition.
  late final AnimationController _a1; // 6 s  – primary bloom
  late final AnimationController _a2; // 9 s  – secondary accent
  late final AnimationController _a3; // 4 s  – bottom heat

  double _brightBoost = 0;

  @override
  void initState() {
    super.initState();
    _a1 = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat(reverse: true);
    _a2 = AnimationController(vsync: this, duration: const Duration(seconds: 9))
      ..forward(); // starts at 0, repeats reverse — different phase
    _a3 = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);

    // Start _a2 at a different point in its cycle for phase offset
    _a2.value = 0.4;
    _a2.repeat(reverse: true);

    widget.controller?.addListener(_onControllerEvent);
  }

  @override
  void didUpdateWidget(FlickerBackground old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onControllerEvent);
      widget.controller?.addListener(_onControllerEvent);
    }
  }

  @override
  void dispose() {
    _a1.dispose();
    _a2.dispose();
    _a3.dispose();
    widget.controller?.removeListener(_onControllerEvent);
    super.dispose();
  }

  void _onControllerEvent() {
    final ctrl = widget.controller!;
    setState(() => _brightBoost = ctrl.brightnessBoost);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Ambient glow layer — isolated repaint boundary ────────────────
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_a1, _a2, _a3]),
              builder: (_, w) => CustomPaint(
                painter: _AmbientPainter(
                  warmth: widget.warmth,
                  t1: _a1.value,
                  t2: _a2.value,
                  t3: _a3.value,
                  brightBoost: _brightBoost,
                ),
                // Hints to Flutter's rasterizer that this paints every frame
                isComplex: true,
                willChange: true,
              ),
            ),
          ),
        ),

        // ── Content ───────────────────────────────────────────────────────
        widget.child,
      ],
    );
  }
}

