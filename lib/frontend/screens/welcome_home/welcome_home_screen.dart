import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../state/user_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/saanjh_logo.dart';

class WelcomeHomeScreen extends StatefulWidget {
  const WelcomeHomeScreen({super.key});

  @override
  State<WelcomeHomeScreen> createState() => _WelcomeHomeScreenState();
}

class _WelcomeHomeScreenState extends State<WelcomeHomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final AnimationController _textCtrl;
  late final AnimationController _ctaCtrl;
  bool _going = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..forward();
    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _ctaCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    Future.delayed(const Duration(milliseconds: 600),
        () { if (mounted) _textCtrl.forward(); });
    Future.delayed(const Duration(milliseconds: 1000),
        () { if (mounted) _ctaCtrl.forward(); });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _ctaCtrl.dispose();
    super.dispose();
  }

  Future<void> _goHome() async {
    if (_going) return;
    HapticFeedback.mediumImpact();
    setState(() => _going = true);
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: GlowBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
              child: Column(
                children: [
                  const Spacer(),
                  _LogoSection(ctrl: _logoCtrl),
                  const SizedBox(height: 48),
                  _TextSection(ctrl: _textCtrl),
                  const Spacer(),
                  _CtaSection(
                    ctrl: _ctaCtrl,
                    going: _going,
                    onGo: _goHome,
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

class _LogoSection extends StatelessWidget {
  final AnimationController ctrl;
  const _LogoSection({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.85 + 0.15 * t,
            child: child,
          ),
        );
      },
      child: const SaanjhLogo(size: 100),
    );
  }
}

class _TextSection extends StatelessWidget {
  final AnimationController ctrl;
  const _TextSection({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Builder(
        builder: (context) {
          final name = UserStore.instance.name;
          return Column(
            children: [
              Text(
                name.isEmpty
                    ? 'Welcome to Saanjh'
                    : 'Welcome,\n$name.',
                style: AppTypography.display(size: 40),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Your living diary is ready.\nShare a voice note whenever\nyou feel the urge.',
                style: AppTypography.serifItalic(size: 20),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CtaSection extends StatelessWidget {
  final AnimationController ctrl;
  final bool going;
  final VoidCallback onGo;

  const _CtaSection({
    required this.ctrl,
    required this.going,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Column(
        children: [
          CtaPrimary(
            label: 'Go to my diaries  →',
            loading: going,
            onPressed: onGo,
          ),
          const SizedBox(height: 16),
          Text(
            'A living diary — kept forever,\nfor the people you love.',
            style: AppTypography.label(
                size: 12.5, color: AppColors.textFaint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
