import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';

class WishScreen extends StatefulWidget {
  final String recipientName;
  const WishScreen({super.key, this.recipientName = 'Papa'});

  @override
  State<WishScreen> createState() => _WishScreenState();
}

enum _WishState { idle, sending, sent }

class _WishScreenState extends State<WishScreen>
    with TickerProviderStateMixin {
  _WishState _state = _WishState.idle;
  late final AnimationController _burstCtrl;
  late final AnimationController _floatCtrl;
  late final AnimationController _pulseCtrl;
  String _selectedWish = '🌟 Thinking of you';

  static const _wishes = [
    '🌟 Thinking of you',
    '💛 Sending love',
    '🎂 Happy Birthday!',
    '🪔 Happy Diwali!',
    '🌙 Eid Mubarak!',
    '🎉 Congratulations!',
    '🙏 Missing you',
    '❤️ Love you',
  ];

  @override
  void initState() {
    super.initState();
    _burstCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _floatCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _burstCtrl.dispose();
    _floatCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendWish() async {
    if (_state != _WishState.idle) return;
    HapticFeedback.mediumImpact();
    setState(() => _state = _WishState.sending);
    await _burstCtrl.forward();
    if (!mounted) return;
    setState(() => _state = _WishState.sent);
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 400));
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0400),
      body: Stack(
        children: [
          // Golden background glow
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, w) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.1),
                    radius: 0.9,
                    colors: [
                      const Color(0xFFFFB800).withValues(
                          alpha: 0.12 + 0.06 * _pulseCtrl.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Particle burst (on sent)
          if (_state == _WishState.sent || _burstCtrl.value > 0)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _burstCtrl,
                builder: (_, w) => CustomPaint(
                  painter: _BurstPainter(progress: _burstCtrl.value),
                ),
              ),
            ),

          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.pop();
                        },
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.06),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 1),
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Colors.white),
                        ),
                      ),
                      const Spacer(),
                      Text('Send a Wish',
                          style: AppTypography.label(
                              size: 14, color: Colors.white.withValues(alpha: 0.7))),
                      const Spacer(),
                      const SizedBox(width: 36),
                    ],
                  ),
                ),

                const Spacer(),

                // Main star / sent check
                AnimatedBuilder(
                  animation: _floatCtrl,
                  builder: (_, child) {
                    return Transform.translate(
                      offset: Offset(0, -8 * _floatCtrl.value),
                      child: child,
                    );
                  },
                  child: _state == _WishState.sent
                      ? _SentState(name: widget.recipientName,
                          wish: _selectedWish)
                      : _IdleState(
                          name: widget.recipientName,
                          pulseCtrl: _pulseCtrl,
                        ),
                ),

                const Spacer(),

                if (_state == _WishState.idle) ...[
                  // Wish type selector
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      separatorBuilder: (_, s) => const SizedBox(width: 8),
                      itemCount: _wishes.length,
                      itemBuilder: (_, i) {
                        final w = _wishes[i];
                        final sel = w == _selectedWish;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedWish = w);
                          },
                          child: AnimatedContainer(
                            duration: AppMotion.fast,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: sel
                                  ? const Color(0xFFFFB800).withValues(alpha: 0.18)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: sel
                                    ? const Color(0xFFFFB800).withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.08),
                                width: 1,
                              ),
                            ),
                            child: Text(w,
                                style: AppTypography.label(
                                  size: 13,
                                  weight: sel ? FontWeight.w600 : FontWeight.w400,
                                  color: sel
                                      ? const Color(0xFFFFD60A)
                                      : Colors.white.withValues(alpha: 0.6),
                                )),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Price note
                  Text(
                    'A special notification for ${widget.recipientName} · ₹29',
                    style: AppTypography.label(
                        size: 12.5,
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  const SizedBox(height: 18),

                  // Send button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: _SendWishButton(
                      wish: _selectedWish,
                      onTap: _sendWish,
                    ),
                  ),
                ],

                if (_state == _WishState.sent) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: double.infinity, height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: Colors.white.withValues(alpha: 0.07),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12), width: 1),
                        ),
                        child: Center(
                          child: Text('Done',
                              style: AppTypography.button(color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ],

                SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdleState extends StatelessWidget {
  final String name;
  final AnimationController pulseCtrl;

  const _IdleState({required this.name, required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (_, child) {
        final t = pulseCtrl.value;
        return Column(
          children: [
            Transform.scale(
              scale: 1.0 + 0.05 * t,
              child: Container(
                width: 130, height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFB800).withValues(alpha: 0.12 + 0.06 * t),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFB800)
                          .withValues(alpha: 0.35 + 0.15 * t),
                      blurRadius: 50 + 20 * t,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🌟', style: TextStyle(fontSize: 56)),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text('Send a Wish to',
                style: AppTypography.body(
                    size: 16, color: Colors.white.withValues(alpha: 0.5))),
            const SizedBox(height: 6),
            Text(name,
                style: AppTypography.display(size: 36).copyWith(
                    color: Colors.white)),
            const SizedBox(height: 10),
            Text(
              'They\'ll feel a special golden moment\n— unlike any regular message.',
              style: AppTypography.serifItalic(
                  size: 15, color: Colors.white.withValues(alpha: 0.45)),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }
}

class _SentState extends StatelessWidget {
  final String name;
  final String wish;
  const _SentState({required this.name, required this.wish});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 110, height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFFB800).withValues(alpha: 0.15),
            border: Border.all(
                color: const Color(0xFFFFD60A).withValues(alpha: 0.5),
                width: 2),
            boxShadow: [
              const BoxShadow(
                color: Color(0x55FFB800),
                blurRadius: 50,
              ),
            ],
          ),
          child: const Center(
            child: Text('✨', style: TextStyle(fontSize: 48)),
          ),
        ),
        const SizedBox(height: 28),
        Text('Wish sent!',
            style: AppTypography.display(size: 36).copyWith(
                color: const Color(0xFFFFD60A))),
        const SizedBox(height: 10),
        Text('$name just received\n"$wish"',
            style: AppTypography.serifItalic(size: 17).copyWith(
                color: Colors.white.withValues(alpha: 0.6)),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB800).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFFFFB800).withValues(alpha: 0.3),
                width: 1),
          ),
          child: Text('₹29 · One-time',
              style: AppTypography.label(
                  size: 12, color: const Color(0xFFFFD60A))),
        ),
      ],
    );
  }
}

class _SendWishButton extends StatefulWidget {
  final String wish;
  final VoidCallback onTap;
  const _SendWishButton({required this.wish, required this.onTap});

  @override
  State<_SendWishButton> createState() => _SendWishButtonState();
}

class _SendWishButtonState extends State<_SendWishButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: AppMotion.fast,
        child: Container(
          width: double.infinity, height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD60A), Color(0xFFFFB800)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB800)
                    .withValues(alpha: _pressed ? 0.3 : 0.5),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'Send wish · ₹29',
              style: AppTypography.button(color: const Color(0xFF3A2000)),
            ),
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double progress;
  _BurstPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final rng = math.Random(42);
    final cx = size.width / 2;
    final cy = size.height * 0.38;

    for (int i = 0; i < 24; i++) {
      final angle = (i / 24) * 2 * math.pi + rng.nextDouble() * 0.2;
      final speed = 80 + rng.nextDouble() * 160;
      final dist = speed * progress;
      final alpha = (1.0 - progress) * 0.9;
      final r = 2.0 + rng.nextDouble() * 5;

      final colors = [
        const Color(0xFFFFD60A),
        const Color(0xFFFFB800),
        const Color(0xFFFF9A40),
        Colors.white,
      ];
      final color = colors[i % colors.length];

      canvas.drawCircle(
        Offset(
          cx + dist * math.cos(angle),
          cy + dist * math.sin(angle),
        ),
        r * (1 - progress * 0.5),
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter o) => o.progress != progress;
}

