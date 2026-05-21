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

/// Shown when the app is opened via an invite deep-link.
/// Receives the inviter's name + id from route extras.
class InviteAcceptScreen extends StatefulWidget {
  final String inviterName;
  final String inviterId;

  const InviteAcceptScreen({
    super.key,
    required this.inviterName,
    required this.inviterId,
  });

  @override
  State<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends State<InviteAcceptScreen>
    with TickerProviderStateMixin {
  late final AnimationController _heroCtrl;
  late final AnimationController _contentCtrl;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _contentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted) _contentCtrl.forward();
    });
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_starting) return;
    HapticFeedback.mediumImpact();
    setState(() => _starting = true);
    await Future.delayed(const Duration(milliseconds: 380));
    if (!mounted) return;
    // Pass inviterId through so auth flow can auto-link the diary after sign-up.
    context.go(
      AppRoutes.phoneNumber,
      extra: {'inviterId': widget.inviterId},
    );
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
              padding: const EdgeInsets.fromLTRB(28, 56, 28, 36),
              child: Column(
                children: [
                  _HeroSection(ctrl: _heroCtrl, inviterName: widget.inviterName),
                  const Spacer(),
                  _ContentSection(
                    ctrl: _contentCtrl,
                    starting: _starting,
                    onSignUp: _signUp,
                    onLater: () => context.go(AppRoutes.home),
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

// ---------------------------------------------------------------------------

class _HeroSection extends StatelessWidget {
  final AnimationController ctrl;
  final String inviterName;
  const _HeroSection({required this.ctrl, required this.inviterName});

  @override
  Widget build(BuildContext context) {
    final fade =
        CurvedAnimation(parent: ctrl, curve: const Interval(0.0, 0.55));
    final slide =
        CurvedAnimation(parent: ctrl, curve: AppMotion.easeSpring);

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final t = slide.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: fade.value,
          child:
              Transform.translate(offset: Offset(0, 22 * (1 - t)), child: child),
        );
      },
      child: Column(
        children: [
          const SaanjhLogo(size: 72),
          const SizedBox(height: 24),
          Text('Saanjh', style: AppTypography.display(size: 36)),
          const SizedBox(height: 20),
          // Emoji heart
          Text('💛', style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 18),
          Text.rich(
            TextSpan(
              style: AppTypography.title(size: 24, weight: FontWeight.w600)
                  .copyWith(height: 1.2),
              children: [
                TextSpan(
                  text: inviterName,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: AppColors.emberBright,
                  ),
                ),
                const TextSpan(text: ' created\na diary for you on Saanjh'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Voice notes, shared moments, and a daily pulse —\njust the two of you.',
            style: AppTypography.serifItalic(size: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ContentSection extends StatelessWidget {
  final AnimationController ctrl;
  final bool starting;
  final VoidCallback onSignUp;
  final VoidCallback onLater;

  const _ContentSection({
    required this.ctrl,
    required this.starting,
    required this.onSignUp,
    required this.onLater,
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
              offset: Offset(0, 16 * (1 - t)), child: child),
        );
      },
      child: Column(
        children: [
          CtaPrimary(
            label: 'Sign up with your number  →',
            loading: starting,
            onPressed: starting ? null : onSignUp,
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onLater,
            child: Text(
              "I'll try it later",
              style: AppTypography.label(
                  size: 13, color: AppColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}

