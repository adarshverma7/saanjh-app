import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../router/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

// Normalised time markers over the 11.5 s sequence
const _kT2  =  2.0 / 11.5;
const _kT4  =  4.0 / 11.5;
const _kT6  =  6.0 / 11.5;
const _kT8  =  8.0 / 11.5;
const _kT10 = 10.0 / 11.5;

double _norm(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);
double _easeOut3(double t) => 1 - math.pow(1 - t, 3).toDouble();
double _easeIn3(double t) => t * t * t;

class OnboardingFilmScreen extends StatefulWidget {
  const OnboardingFilmScreen({super.key});

  @override
  State<OnboardingFilmScreen> createState() => _OnboardingFilmScreenState();
}

class _OnboardingFilmScreenState extends State<OnboardingFilmScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _showSkip = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 11500),
    )
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _complete();
      })
      ..forward();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSkip = true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_exiting) return;
    _exiting = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_film', true);
    if (!mounted) return;
    context.go(AppRoutes.phoneNumber);
  }

  Future<void> _skip() async {
    if (_exiting) return;
    _ctrl.stop();
    await _complete();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          // Ambient visuals — phones, waveform, line, heart
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => CustomPaint(
                painter: _FilmPainter(_ctrl.value),
              ),
            ),
          ),
          // Narrative text overlays — Frames 1 & 4
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => _FilmTextLayer(t: _ctrl.value),
            ),
          ),
          // Title card — Frame 6
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => _TitleLayer(t: _ctrl.value),
            ),
          ),
          // Skip button — appears after 2 s
          Positioned(
            top: topPad + 16,
            right: 24,
            child: AnimatedOpacity(
              opacity: _showSkip ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              child: GestureDetector(
                onTap: _skip,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Skip →',
                    style: AppTypography.label(
                      size: 13,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Film canvas
// ---------------------------------------------------------------------------

class _FilmPainter extends CustomPainter {
  final double t;
  _FilmPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Fade-to-black multiplier applied from mid-Frame-5 onwards
    final fadeToBlack =
        _easeIn3(_norm(t, _kT8 + (_kT10 - _kT8) * 0.55, _kT10));

    // ─── Frame 1–5: left phone ──────────────────────────────────────────────
    final leftOpacity = (_easeOut3(_norm(t, 0.0, _kT2 * 0.45)) *
            (1 - _easeIn3(_norm(t, _kT8 + (_kT10 - _kT8) * 0.4, _kT10))))
        .clamp(0.0, 1.0) *
        (1 - fadeToBlack);
    if (leftOpacity > 0) _drawPhone(canvas, Offset(cx * 0.46, cy), leftOpacity);

    // ─── Frame 2–3: waveform ────────────────────────────────────────────────
    final waveOpacity = (_easeOut3(_norm(t, _kT2, _kT2 + 0.04)) *
            (1 - _easeIn3(_norm(t, _kT4 - 0.03, _kT4))))
        .clamp(0.0, 1.0);
    if (waveOpacity > 0) _drawWaveform(canvas, size, cx, cy, waveOpacity);

    // ─── Frame 3: travelling line ───────────────────────────────────────────
    final lineOpacity = (_easeOut3(_norm(t, _kT4, _kT4 + 0.02)) *
            (1 - _easeIn3(_norm(t, _kT6 - 0.02, _kT6))))
        .clamp(0.0, 1.0);
    if (lineOpacity > 0) _drawTravelLine(canvas, size, cy, lineOpacity);

    // ─── Frame 4–5: right phone ─────────────────────────────────────────────
    final rightOpacity =
        (_easeOut3(_norm(t, _kT6, _kT6 + (_kT8 - _kT6) * 0.4)) *
                (1 - _easeIn3(_norm(t, _kT8 + (_kT10 - _kT8) * 0.4, _kT10))))
            .clamp(0.0, 1.0) *
            (1 - fadeToBlack);
    if (rightOpacity > 0) {
      _drawPhone(canvas, Offset(cx * 1.54, cy), rightOpacity);
    }

    // ─── Frame 5: heart ─────────────────────────────────────────────────────
    final heartOpacity =
        (_easeOut3(_norm(t, _kT8, _kT8 + 0.04)) *
                (1 - _easeIn3(_norm(t, _kT10 - 0.05, _kT10))))
            .clamp(0.0, 1.0) *
            (1 - fadeToBlack);
    if (heartOpacity > 0) _drawHeart(canvas, cx, cy, heartOpacity);

    // ─── Fade-to-black overlay ───────────────────────────────────────────────
    if (fadeToBlack > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = AppColors.ink.withValues(alpha: fadeToBlack),
      );
    }
  }

  void _drawPhone(Canvas canvas, Offset centre, double opacity) {
    const w = 50.0;
    const h = 86.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: centre, width: w, height: h),
      const Radius.circular(10),
    );

    // Ambient glow
    canvas.drawRRect(
      rect.inflate(22),
      Paint()
        ..color = AppColors.emberWarm.withValues(alpha: opacity * 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 38),
    );
    // Body
    canvas.drawRRect(
      rect,
      Paint()..color = AppColors.inkRaised.withValues(alpha: opacity),
    );
    // Inner screen warmth
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: w - 8, height: h - 16),
        const Radius.circular(6),
      ),
      Paint()..color = AppColors.emberWarm.withValues(alpha: opacity * 0.10),
    );
    // Border
    canvas.drawRRect(
      rect,
      Paint()
        ..color = AppColors.emberWarm.withValues(alpha: opacity * 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _drawWaveform(
      Canvas canvas, Size size, double cx, double cy, double opacity) {
    final localT = _norm(t, _kT2, _kT4);
    const barCount = 30;
    const barW = 2.5;
    const barGap = 4.5;
    const totalW = barCount * (barW + barGap);

    final paint = Paint()
      ..color = AppColors.emberWarm.withValues(alpha: opacity * 0.82)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;

    for (int i = 0; i < barCount; i++) {
      final x = cx - totalW / 2 + i * (barW + barGap) + barW / 2;
      final phase = i / barCount * math.pi * 4;
      final breathe = math.sin(localT * math.pi * 3 + phase);
      final envelope = math.sin(i / barCount * math.pi);
      final barH = (8.0 + breathe * 16 * envelope + envelope * 22).clamp(3.0, 54.0);
      canvas.drawLine(
        Offset(x, cy - barH / 2),
        Offset(x, cy + barH / 2),
        paint,
      );
    }
  }

  void _drawTravelLine(Canvas canvas, Size size, double cy, double opacity) {
    final progress = _easeOut3(_norm(t, _kT4, _kT6));
    final startX = size.width * 0.08;
    final endX = size.width * 0.92;
    final headX = startX + (endX - startX) * progress;

    // Glowing trail
    canvas.drawLine(
      Offset(startX, cy),
      Offset(headX, cy),
      Paint()
        ..color = AppColors.emberWarm.withValues(alpha: opacity * 0.18)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Core line
    canvas.drawLine(
      Offset(startX, cy),
      Offset(headX, cy),
      Paint()
        ..color = AppColors.emberWarm.withValues(alpha: opacity * 0.65)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    // Leading dot — outer glow
    canvas.drawCircle(
      Offset(headX, cy),
      6,
      Paint()
        ..color = AppColors.emberWarm.withValues(alpha: opacity * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // Leading dot — core
    canvas.drawCircle(
      Offset(headX, cy),
      2.8,
      Paint()..color = AppColors.emberWarm.withValues(alpha: opacity),
    );
  }

  void _drawHeart(Canvas canvas, double cx, double cy, double opacity) {
    const scale = 1.5;
    const yCenter = -2.5; // visual centring correction for this formula
    final heartT = _norm(t, _kT8, _kT10);
    final pulse = 1.0 + math.sin(heartT * math.pi) * 0.18;

    final path = Path();
    bool first = true;
    for (int i = 0; i <= 128; i++) {
      final a = 2 * math.pi * i / 128;
      final sin3 = math.pow(math.sin(a), 3).toDouble();
      final yMath = 13 * math.cos(a) -
          5 * math.cos(2 * a) -
          2 * math.cos(3 * a) -
          math.cos(4 * a);
      final px = cx + scale * pulse * 16 * sin3;
      final py = cy - scale * pulse * (yMath - yCenter);
      if (first) {
        path.moveTo(px, py);
        first = false;
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();

    // Glow halo
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.emberWarm.withValues(alpha: opacity * 0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    // Solid fill
    canvas.drawPath(
      path,
      Paint()..color = AppColors.emberWarm.withValues(alpha: opacity * 0.90),
    );
  }

  @override
  bool shouldRepaint(_FilmPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Text overlays — Frames 1 and 4
// ---------------------------------------------------------------------------

class _FilmTextLayer extends StatelessWidget {
  final double t;
  const _FilmTextLayer({required this.t});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Frame 1: "somewhere in the city…"
    final text1 =
        (_easeOut3(_norm(t, 0.04, _kT2 * 0.65)) *
                (1 - _easeIn3(_norm(t, _kT4 * 0.72, _kT4))))
            .clamp(0.0, 1.0);

    // Frame 4: "somewhere they remember you."
    final text2 =
        (_easeOut3(_norm(t, _kT6 + 0.012, _kT6 + (_kT8 - _kT6) * 0.48)) *
                (1 - _easeIn3(_norm(t, _kT8 - (_kT8 - _kT6) * 0.28, _kT8))))
            .clamp(0.0, 1.0);

    return Stack(
      children: [
        if (text1 > 0)
          Positioned(
            left: 40,
            right: 40,
            top: size.height * 0.24,
            child: Opacity(
              opacity: text1,
              child: Text(
                'somewhere in the city…',
                textAlign: TextAlign.center,
                style: AppTypography.serifItalic(size: 18),
              ),
            ),
          ),
        if (text2 > 0)
          Positioned(
            left: 40,
            right: 40,
            top: size.height * 0.24,
            child: Opacity(
              opacity: text2,
              child: Text(
                'somewhere they\nremember you.',
                textAlign: TextAlign.center,
                style: AppTypography.serifItalic(size: 18),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Title card — Frame 6
// ---------------------------------------------------------------------------

class _TitleLayer extends StatelessWidget {
  final double t;
  const _TitleLayer({required this.t});

  @override
  Widget build(BuildContext context) {
    final titleFade = _easeOut3(_norm(t, _kT10, _kT10 + 0.08));
    final subFade = _easeOut3(_norm(t, _kT10 + 0.05, _kT10 + 0.14));

    if (titleFade <= 0) return const SizedBox.shrink();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: titleFade,
              child: Text(
                'Saanjh.',
                style: AppTypography.display(size: 52).copyWith(
                  color: AppColors.emberWarm,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (subFade > 0)
              Opacity(
                opacity: subFade,
                child: Text(
                  'A living diary with the people who matter.',
                  textAlign: TextAlign.center,
                  style: AppTypography.serifItalic(size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

