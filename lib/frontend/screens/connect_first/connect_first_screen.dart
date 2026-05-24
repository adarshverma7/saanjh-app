import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/onboarding_background.dart';

class ConnectFirstScreen extends StatefulWidget {
  const ConnectFirstScreen({super.key});

  @override
  State<ConnectFirstScreen> createState() => _ConnectFirstScreenState();
}

class _ConnectFirstScreenState extends State<ConnectFirstScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _fade(double delay, Widget child) {
    final anim = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(delay, (delay + 0.5).clamp(0.0, 1.0),
          curve: AppMotion.easeOut),
    );
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

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: OnboardingBackground()),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPad + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fade(
                    0.0,
                    _BackButton(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        context.pop();
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                  _fade(
                    0.08,
                    Text(
                      'Who do you want to\nstart a diary with?',
                      style: AppTypography.title(
                              size: 28, weight: FontWeight.w600)
                          .copyWith(
                              fontStyle: FontStyle.italic, height: 1.18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _fade(
                    0.15,
                    Text(
                      'Find someone already on Saanjh, or share a link they can open anywhere.',
                      style: AppTypography.serifItalic(size: 16),
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Cards
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: _fade(
                            0.22,
                            _ConnectCard(
                              icon: Icons.person_search_rounded,
                              title: 'Find on Saanjh',
                              subtitle:
                                  'See which of your contacts are already here',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                context.push(AppRoutes.discover);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _fade(
                            0.30,
                            _ConnectCard(
                              icon: Icons.person_add_rounded,
                              title: 'Invite someone',
                              subtitle:
                                  'Share a link via WhatsApp, iMessage, email — wherever they are',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                context.push(AppRoutes.invite);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _fade(
                    0.40,
                    Center(
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          context.go(AppRoutes.home);
                        },
                        child: Text(
                          "I'll do this later  →",
                          style: AppTypography.label(
                              size: 13.5, color: AppColors.textFaint),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _fade(
                    0.46,
                    Center(
                      child: Text(
                        'You can add more people anytime from the app.',
                        style: AppTypography.label(
                            size: 12, color: AppColors.textFaint),
                        textAlign: TextAlign.center,
                      ),
                    ),
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

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.08), width: 1),
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 14, color: Color(0x9EF5EFE8)),
      ),
    );
  }
}

class _ConnectCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ConnectCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends State<_ConnectCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        decoration: BoxDecoration(
          color: _pressed
              ? AppColors.ember.withValues(alpha: 0.11)
              : AppColors.ember.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _pressed
                ? AppColors.emberWarm.withValues(alpha: 0.42)
                : AppColors.emberWarm.withValues(alpha: 0.18),
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.ember.withValues(alpha: 0.14),
                border: Border.all(
                  color: AppColors.emberWarm.withValues(alpha: 0.26),
                  width: 1,
                ),
              ),
              child: Icon(widget.icon, size: 24, color: AppColors.emberWarm),
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              style:
                  AppTypography.title(size: 20, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              widget.subtitle,
              style: AppTypography.serifItalic(size: 15),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}
