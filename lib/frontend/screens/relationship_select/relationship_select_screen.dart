import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../router/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/onboarding_background.dart';
import '../../widgets/onboarding_top_bar.dart';
import '../pre_commit/pre_commit_screen.dart' show kPreCommitRelationKey;

class RelationshipSelectScreen extends StatefulWidget {
  const RelationshipSelectScreen({super.key});

  @override
  State<RelationshipSelectScreen> createState() =>
      _RelationshipSelectScreenState();
}

class _RelationshipSelectScreenState extends State<RelationshipSelectScreen>
    with TickerProviderStateMixin {
  static const _relations = <_Relation>[
    _Relation('parent', '🌅', 'My parent or parents', 'The people who raised me'),
    _Relation('child', '🌱', 'My child or children', 'The next generation, near or far'),
    _Relation('partner', '💛', 'My partner or spouse', 'The person I share my days with'),
    _Relation('other', '✨', 'Someone else close to me', 'A sibling, friend, mentor — anyone'),
  ];

  final List<String> _selected = [];
  bool _continuing = false;

  late final AnimationController _entranceCtrl;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _loadPreCommitSelection();
  }

  // Pre-select whichever relation the user tapped in PreCommitScreen so this
  // screen feels like a confirmation rather than a repeated question.
  Future<void> _loadPreCommitSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final preCommit = prefs.getString(kPreCommitRelationKey);
    if (!mounted || preCommit == null) return;
    final match = _relations.where((r) => r.id == preCommit);
    if (match.isNotEmpty) {
      setState(() => _selected.add(match.first.id));
    }
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _continue() async {
    if (_continuing || _selected.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _continuing = true);
    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    context.push(AppRoutes.phoneNumber);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _continuing = false);
  }

  Future<void> _skip() async {
    if (_continuing) return;
    HapticFeedback.selectionClick();
    setState(() => _continuing = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    context.push(AppRoutes.phoneNumber);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _continuing = false);
  }

  void _back() {
    HapticFeedback.selectionClick();
    context.go(AppRoutes.splash);
  }

  @override
  Widget build(BuildContext context) {
    final continueLabel = _selected.length >= 2
        ? 'Continue with ${_selected.length}  →'
        : 'Continue  →';

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: OnboardingBackground()),
          SafeArea(
            child: Column(
              children: [
                OnboardingTopBar(
                  currentStep: 1,
                  totalSteps: 4,
                  onBack: _back,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _StaggerFade(
                        controller: _entranceCtrl,
                        delay: 0.08,
                        child: Text(
                          'STEP 1 — WHO IS THIS FOR?',
                          style: AppTypography.eyebrow(
                            size: 11,
                            color: AppColors.emberBright,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _StaggerFade(
                        controller: _entranceCtrl,
                        delay: 0.15,
                        child: _Heading(),
                      ),
                      const SizedBox(height: 12),
                      _StaggerFade(
                        controller: _entranceCtrl,
                        delay: 0.23,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Text(
                            "Pick one — or as many as you'd like. We'll start with one person per diary. You can add more people or build a family group later.",
                            style: AppTypography.body(
                              size: 15,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                      for (int i = 0; i < _relations.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _StaggerFade(
                          controller: _entranceCtrl,
                          delay: 0.32 + i * 0.07,
                          child: _OptionCard(
                            relation: _relations[i],
                            selected: _selected.contains(_relations[i].id),
                            onTap: () => _toggle(_relations[i].id),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _StaggerFade(
                  controller: _entranceCtrl,
                  delay: 0.66,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: Column(
                      children: [
                        CtaPrimary(
                          label: continueLabel,
                          loading: _continuing && _selected.isNotEmpty,
                          onPressed: _selected.isEmpty ? null : _continue,
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: _skip,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textMuted,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            "Skip — I'll decide later",
                            style: AppTypography.label(
                              size: 13,
                              color: AppColors.textMuted,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Relation {
  final String id;
  final String emoji;
  final String label;
  final String sub;
  const _Relation(this.id, this.emoji, this.label, this.sub);
}

class _Heading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final base = AppTypography.title(size: 40, weight: FontWeight.w600)
        .copyWith(height: 1.08, letterSpacing: -0.015 * 40);
    final italicEmber = base.copyWith(
      fontStyle: FontStyle.italic,
      color: AppColors.emberBright,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'Who do you want\nto share Saanjh '),
          TextSpan(text: 'with?', style: italicEmber),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final _Relation relation;
  final bool selected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.relation,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: AppMotion.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.ember.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.emberWarm
                : Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.ember.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: AppMotion.easeOut,
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.ember.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  relation.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    relation.label,
                    style: AppTypography.body(
                      size: 15,
                      weight: FontWeight.w600,
                      color: AppColors.text,
                    ).copyWith(letterSpacing: -0.005 * 15, height: 1.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    relation.sub,
                    style: AppTypography.body(
                      size: 12.5,
                      weight: FontWeight.w400,
                      color: selected
                          ? AppColors.textMuted
                          : AppColors.textFaint,
                    ).copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _CheckCircle(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  final bool selected;
  const _CheckCircle({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: AppMotion.easeOut,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.emberWarm : Colors.transparent,
        border: Border.all(
          color: selected
              ? AppColors.emberWarm
              : Colors.white.withValues(alpha: 0.18),
          width: 1.5,
        ),
      ),
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 200),
        curve: AppMotion.easeSpring,
        child: AnimatedOpacity(
          opacity: selected ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: AppMotion.easeOut,
          child: Center(
            child: CustomPaint(
              size: const Size(12, 12),
              painter: _CheckPainter(),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 12;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(2.5 * s, 6.5 * s)
      ..lineTo(5 * s, 9 * s)
      ..lineTo(9.5 * s, 3.5 * s);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _StaggerFade extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final Widget child;

  const _StaggerFade({
    required this.controller,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final interval = Interval(delay, (delay + 0.45).clamp(0.0, 1.0), curve: AppMotion.easeOut);
    final anim = CurvedAnimation(parent: controller, curve: interval);
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) {
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - anim.value)),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}
