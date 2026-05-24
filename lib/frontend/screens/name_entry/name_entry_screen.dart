import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../state/user_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/onboarding_background.dart';
import '../../widgets/onboarding_top_bar.dart';

class NameEntryScreen extends StatefulWidget {
  const NameEntryScreen({super.key});

  @override
  State<NameEntryScreen> createState() => _NameEntryScreenState();
}

class _NameEntryScreenState extends State<NameEntryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final TextEditingController _nameCtrl;
  final _focusNode = FocusNode();
  bool _continuing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _nameCtrl = TextEditingController(text: UserStore.instance.name);
    _nameCtrl.addListener(() => setState(() {}));

    // Auto-focus the field after entrance animation settles.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _nameCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isValid => _nameCtrl.text.trim().length >= 2;

  Future<void> _continue() async {
    if (!_isValid || _continuing) return;
    HapticFeedback.lightImpact();
    setState(() => _continuing = true);
    await UserStore.instance.setName(_nameCtrl.text.trim());
    await UserStore.instance.setOnboarded(true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    context.go(AppRoutes.connectFirst);
  }

  Widget _fade({required double delay, required Widget child}) {
    final interval = Interval(
      delay, (delay + 0.55).clamp(0.0, 1.0),
      curve: AppMotion.easeOut,
    );
    final anim = CurvedAnimation(parent: _ctrl, curve: interval);
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
            offset: Offset(0, 14 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
  }

  // Live avatar preview derived from what the user is typing.
  String get _liveInitial {
    final t = _nameCtrl.text.trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: OnboardingBackground()),
          SafeArea(
            child: Column(
              children: [
                OnboardingTopBar(
                  currentStep: 4,
                  totalSteps: 4,
                  onBack: () {
                    HapticFeedback.selectionClick();
                    context.pop();
                  },
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fade(
                          delay: 0.06,
                          child: Text(
                            'STEP 4 — YOUR NAME',
                            style: AppTypography.eyebrow(
                              size: 11,
                              color: AppColors.emberBright,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _fade(
                          delay: 0.14,
                          child: Text.rich(
                            TextSpan(
                              style: AppTypography.title(
                                      size: 38,
                                      weight: FontWeight.w600)
                                  .copyWith(
                                      height: 1.08,
                                      letterSpacing: -0.015 * 38),
                              children: [
                                const TextSpan(text: 'What should\nwe call '),
                                TextSpan(
                                  text: 'you?',
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: AppColors.emberBright,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _fade(
                          delay: 0.22,
                          child: Text(
                            'This is how your diary connections will see you.',
                            style: AppTypography.body(
                                size: 15,
                                color: AppColors.textMuted),
                          ),
                        ),

                        const SizedBox(height: 36),

                        // ── Live avatar preview ──────────────────────────
                        _fade(
                          delay: 0.30,
                          child: Center(
                            child: _AvatarPreview(initial: _liveInitial),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── Name field ───────────────────────────────────
                        _fade(
                          delay: 0.38,
                          child: _NameField(
                            controller: _nameCtrl,
                            focusNode: _focusNode,
                            onSubmitted: (_) => _continue(),
                          ),
                        ),

                        const SizedBox(height: 12),
                        _fade(
                          delay: 0.44,
                          child: Text(
                            'At least 2 characters. You can change this anytime.',
                            style: AppTypography.label(
                                size: 12,
                                color: AppColors.textFaint),
                          ),
                        ),

                        const SizedBox(height: 36),

                        // ── CTA ──────────────────────────────────────────
                        _fade(
                          delay: 0.52,
                          child: CtaPrimary(
                            label: 'Continue  →',
                            loading: _continuing,
                            onPressed: _isValid ? _continue : null,
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

// ─── Avatar preview ───────────────────────────────────────────────────────────

class _AvatarPreview extends StatelessWidget {
  final String initial;
  const _AvatarPreview({required this.initial});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.easeOut,
      width: 88,
      height: 88,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.emberGradient,
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: AppMotion.fast,
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: child,
          ),
          child: Text(
            initial,
            key: ValueKey(initial),
            style: AppTypography.display(size: 44).copyWith(
              color: Colors.white,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Name field ───────────────────────────────────────────────────────────────

class _NameField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;

  const _NameField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textCapitalization: TextCapitalization.words,
      keyboardType: TextInputType.name,
      textInputAction: TextInputAction.done,
      style: AppTypography.title(size: 26),
      cursorColor: AppColors.emberWarm,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: 'e.g. Adarsh',
        hintStyle:
            AppTypography.title(size: 26).copyWith(color: AppColors.textFaint),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.10), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:
              const BorderSide(color: AppColors.emberWarm, width: 1.5),
        ),
      ),
    );
  }
}
