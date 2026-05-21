import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/saanjh_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _heroCtrl;
  late final AnimationController _taglineCtrl;
  late final AnimationController _ctaCtrl;
  late final AnimationController _signinCtrl;

  bool _exiting = false;
  bool _loadingStart = false;
  bool _loadingInvite = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    _heroCtrl = AnimationController(vsync: this, duration: AppMotion.hero);
    _taglineCtrl = AnimationController(vsync: this, duration: AppMotion.slow);
    _ctaCtrl = AnimationController(vsync: this, duration: AppMotion.slow);
    _signinCtrl = AnimationController(vsync: this, duration: AppMotion.slow);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _heroCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _taglineCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _ctaCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _signinCtrl.forward();
    });
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _taglineCtrl.dispose();
    _ctaCtrl.dispose();
    _signinCtrl.dispose();
    super.dispose();
  }

  Future<void> _getStarted() async {
    if (_exiting) return;
    setState(() => _loadingStart = true);
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 380));
    if (!mounted) return;
    setState(() => _exiting = true);
    await Future.delayed(AppMotion.medium);
    if (!mounted) return;
    context.go(AppRoutes.onboardingIntro);
  }

  Future<void> _haveInvite() async {
    if (_exiting) return;
    setState(() => _loadingInvite = true);
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 380));
    if (!mounted) return;
    setState(() => _exiting = true);
    await Future.delayed(AppMotion.medium);
    if (!mounted) return;
    context.go(AppRoutes.inviteAccept);
  }

  Future<void> _signIn() async {
    if (_exiting) return;
    HapticFeedback.selectionClick();
    setState(() => _exiting = true);
    await Future.delayed(AppMotion.medium);
    if (!mounted) return;
    context.go(AppRoutes.phoneNumber);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: AnimatedOpacity(
        opacity: _exiting ? 0 : 1,
        duration: AppMotion.medium,
        curve: AppMotion.easeOut,
        child: AnimatedScale(
          scale: _exiting ? 0.97 : 1.0,
          duration: AppMotion.medium,
          curve: AppMotion.easeOut,
          child: Stack(
            children: [
              const Positioned.fill(child: GlowBackground()),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final isShort = c.maxHeight < 720;
                    final topPad = isShort ? 56.0 : 70.0;
                    final logoSize = isShort ? 104.0 : 124.0;
                    final titleSize = isShort ? 48.0 : 56.0;
                    final taglineSize = isShort ? 18.0 : 20.0;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(28, topPad, 28, 24),
                      child: Column(
                        children: [
                          SizedBox(height: c.maxHeight * 0.04),
                          _Hero(
                            controller: _heroCtrl,
                            logoSize: logoSize,
                            titleSize: titleSize,
                          ),
                          _Tagline(controller: _taglineCtrl, size: taglineSize),
                          const Spacer(),
                          _CtaStack(
                            controller: _ctaCtrl,
                            loadingStart: _loadingStart,
                            loadingInvite: _loadingInvite,
                            onStart: _getStarted,
                            onInvite: _haveInvite,
                          ),
                          _SignIn(
                            controller: _signinCtrl,
                            onTap: _signIn,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final AnimationController controller;
  final double logoSize;
  final double titleSize;

  const _Hero({
    required this.controller,
    required this.logoSize,
    required this.titleSize,
  });

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: controller, curve: const Interval(0.0, 0.6));
    final transform = CurvedAnimation(parent: controller, curve: AppMotion.easeSpring);
    return AnimatedBuilder(
      animation: controller,
      builder: (_, child) {
        final t = transform.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: fade.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - t)),
            child: Transform.scale(
              scale: 0.94 + 0.06 * t,
              child: child,
            ),
          ),
        );
      },
      child: Column(
        children: [
          SaanjhLogo(size: logoSize),
          const SizedBox(height: 32),
          Text('Saanjh', style: AppTypography.display(size: titleSize)),
          const SizedBox(height: 8),
          Text('सांझ', style: AppTypography.devanagari()),
        ],
      ),
    );
  }
}

class _Tagline extends StatelessWidget {
  final AnimationController controller;
  final double size;

  const _Tagline({required this.controller, required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            'A living diary — kept forever,\nfor the people you love.',
            textAlign: TextAlign.center,
            style: AppTypography.serifItalic(size: size),
          ),
        ),
      ),
    );
  }
}

class _CtaStack extends StatelessWidget {
  final AnimationController controller;
  final bool loadingStart;
  final bool loadingInvite;
  final VoidCallback onStart;
  final VoidCallback onInvite;

  const _CtaStack({
    required this.controller,
    required this.loadingStart,
    required this.loadingInvite,
    required this.onStart,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    final busy = loadingStart || loadingInvite;
    return AnimatedBuilder(
      animation: controller,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          children: [
            CtaPrimary(
              label: 'Get started',
              loading: loadingStart,
              onPressed: busy ? null : onStart,
            ),
            const SizedBox(height: 11),
            CtaGhost(
              label: 'I received an invite',
              onPressed: busy ? null : onInvite,
            ),
          ],
        ),
      ),
    );
  }
}

class _SignIn extends StatelessWidget {
  final AnimationController controller;
  final VoidCallback onTap;

  const _SignIn({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 4),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: AppTypography.label(size: 13, color: AppColors.textMuted),
              children: [
                const TextSpan(text: 'Already have an account?  '),
                TextSpan(
                  text: 'Sign in',
                  style: AppTypography.label(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.emberBright,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
