import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../services/share_card_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/milestone_share_card.dart';

class StreakMilestoneScreen extends StatefulWidget {
  final String diaryId;
  final String contactName;
  final int milestone;

  const StreakMilestoneScreen({
    super.key,
    required this.diaryId,
    required this.contactName,
    required this.milestone,
  });

  @override
  State<StreakMilestoneScreen> createState() => _StreakMilestoneScreenState();
}

class _StreakMilestoneScreenState extends State<StreakMilestoneScreen>
    with TickerProviderStateMixin {
  late final AnimationController _breatheCtrl;
  late final AnimationController _burstCtrl;
  late final AnimationController _enterCtrl;
  final _cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.xSlow,
    )..forward();

    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) HapticFeedback.mediumImpact();
    });
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _burstCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  String get _tree {
    final m = widget.milestone;
    if (m >= 90) return '🌸';
    if (m >= 60) return '🎋';
    if (m >= 30) return '🌲';
    return '🌿';
  }

  String get _label {
    final n = widget.contactName.split(' ').first;
    return switch (widget.milestone) {
      7   => 'Your first week. Keep going. 🌿',
      14  => 'Two weeks of showing up. 🌿',
      30  => 'One month. $n has heard your voice every day. 🌲',
      60  => 'Deep roots. You\'ve built something real. 🎋',
      90  => 'In full bloom. A free Memory Book is yours. 🌸',
      100 => '100 days of presence. This is extraordinary. 🌸',
      365 => 'A full year. Your voices are woven into each other\'s lives. 🌸✨',
      _   => 'You\'re showing up. Keep going. 🔥',
    };
  }

  Future<void> _share() async {
    HapticFeedback.lightImpact();
    await ShareCardService.instance.shareStreakCard(
      _cardKey,
      widget.milestone,
      widget.contactName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.inkDeep,
      body: Stack(
        children: [
          // Confetti burst
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _burstCtrl,
              builder: (_, _) => CustomPaint(
                painter: _MilestoneBurstPainter(progress: _burstCtrl.value),
              ),
            ),
          ),

          // Ambient amber background glow
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _breatheCtrl,
              builder: (_, _) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.1),
                    radius: 0.80,
                    colors: [
                      AppColors.emberWarm.withValues(
                          alpha: 0.06 + _breatheCtrl.value * 0.03),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Off-screen share card (captured for sharing)
          Offstage(
            child: MilestoneShareCard(
              key: _cardKey,
              streakDays: widget.milestone,
              contactName: widget.contactName,
              milestoneLabel: _label,
            ),
          ),

          // Content
          SafeArea(
            child: AnimatedBuilder(
              animation: _enterCtrl,
              builder: (_, child) {
                final t = Curves.easeOutCubic.transform(_enterCtrl.value);
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                      offset: Offset(0, 28 * (1 - t)), child: child),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 32),
                child: Column(
                  children: [
                    // Close
                    Align(
                      alignment: Alignment.topLeft,
                      child: GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                Colors.white.withValues(alpha: 0.06),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.10),
                                width: 1),
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Color(0x9EF5EFE8)),
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Breathing tree
                    AnimatedBuilder(
                      animation: _breatheCtrl,
                      builder: (_, _) => Transform.scale(
                        scale: 1.0 + 0.07 * _breatheCtrl.value,
                        child: Text(
                          _tree,
                          style: const TextStyle(fontSize: 84),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Milestone number
                    Text(
                      '🔥  ${widget.milestone}',
                      style: AppTypography.display(size: 64).copyWith(
                        color: AppColors.emberWarm,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 24),

                    // Milestone label
                    Text(
                      _label,
                      style: AppTypography.serifItalic(size: 22).copyWith(
                        color: AppColors.text,
                        height: 1.38,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    // "with [Name]"
                    Text(
                      'with ${widget.contactName.split(' ').first}',
                      style: AppTypography.serifItalic(size: 17),
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(),

                    // Share button
                    GestureDetector(
                      onTap: _share,
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: AppColors.emberGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.ember.withValues(alpha: 0.45),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Share this milestone  →',
                            style: AppTypography.button(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Continue
                    TextButton(
                      onPressed: () => context.pop(),
                      child: Text(
                        'Continue',
                        style: AppTypography.label(
                            size: 14, color: AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Soft gift upsell — only for meaningful milestones
                    if (widget.milestone >= 30)
                      TextButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          context.push(AppRoutes.memoryBook, extra: {
                            'diaryId': widget.diaryId,
                            'isGift': true,
                          });
                        },
                        child: Text(
                          '🎁  Gift them this moment as a book →',
                          style: AppTypography.label(
                              size: 12.5, color: AppColors.textFaint),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Full-screen confetti burst ───────────────────────────────────────────────

class _MilestoneBurstPainter extends CustomPainter {
  final double progress;
  _MilestoneBurstPainter({required this.progress});

  static const _colors = [
    AppColors.emberWarm,
    AppColors.emberBright,
    Color(0xFFFFD60A),
    Colors.white,
    Color(0xFFFF9500),
    Color(0xFFFFC107),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1.0) return;
    final rng = math.Random(77);
    final cx = size.width / 2;
    final cy = size.height * 0.40;

    for (int i = 0; i < 52; i++) {
      final angle =
          (i / 52) * 2 * math.pi + rng.nextDouble() * 0.24;
      final speed = 55.0 + rng.nextDouble() * 280;
      final dist = speed * progress;
      final alpha = (1.0 - progress) * 0.88;
      final r = 2.0 + rng.nextDouble() * 6.5;
      canvas.drawCircle(
        Offset(cx + dist * math.cos(angle),
            cy + dist * math.sin(angle)),
        r * (1 - progress * 0.42),
        Paint()
          ..color = _colors[i % _colors.length].withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_MilestoneBurstPainter o) => o.progress != progress;
}
