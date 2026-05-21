import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../router/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/onboarding_background.dart';

// SharedPreferences key written here, read in RelationshipSelectScreen.
const kPreCommitRelationKey = 'onboarding_precommit';

class PreCommitScreen extends StatefulWidget {
  const PreCommitScreen({super.key});

  @override
  State<PreCommitScreen> createState() => _PreCommitScreenState();
}

class _PreCommitScreenState extends State<PreCommitScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterCtrl;

  static const _options = <_Option>[
    _Option(
      emoji: '👩‍👧',
      label: 'Parent or Child',
      sub: 'The people who raised me,\nor my own kids',
      relationId: 'parent',
    ),
    _Option(
      emoji: '💑',
      label: 'Partner',
      sub: 'The person I share\nmy life with',
      relationId: 'partner',
    ),
    _Option(
      emoji: '👫',
      label: 'Best friend',
      sub: 'Someone who gets me\nlike no one else',
      relationId: 'other',
    ),
    _Option(
      emoji: '👨‍👩‍👧‍👦',
      label: 'My family',
      sub: 'A group of people\nI want to stay close to',
      relationId: 'parent',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
    )..forward();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(_Option option) async {
    HapticFeedback.selectionClick();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPreCommitRelationKey, option.relationId);
    if (!mounted) return;
    context.push(AppRoutes.relationshipSelect);
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
                const SizedBox(height: 52),

                // Heading — staggered entry
                AnimatedBuilder(
                  animation: _enterCtrl,
                  builder: (_, child) {
                    final t = Curves.easeOutCubic
                        .transform(_enterCtrl.value);
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 16 * (1 - t)),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        Text(
                          'Who do you want\nto stay close to?',
                          style: AppTypography.title(size: 30),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Just tap one to get started.',
                          style: AppTypography.serifItalic(size: 16),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 44),

                // 2 × 2 grid of option cards
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      physics: const NeverScrollableScrollPhysics(),
                      children: List.generate(_options.length, (i) {
                        final delay = 0.15 + i * 0.10;
                        return AnimatedBuilder(
                          animation: _enterCtrl,
                          builder: (_, child) {
                            final raw = ((_enterCtrl.value - delay) /
                                    (1.0 - delay))
                                .clamp(0.0, 1.0);
                            final t = Curves.easeOutCubic.transform(raw);
                            return Opacity(
                              opacity: t,
                              child: Transform.translate(
                                offset: Offset(0, 20 * (1 - t)),
                                child: child,
                              ),
                            );
                          },
                          child: _OptionCard(
                            option: _options[i],
                            onTap: () => _pick(_options[i]),
                          ),
                        );
                      }),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Skip
                TextButton(
                  onPressed: () => context.push(AppRoutes.relationshipSelect),
                  child: Text(
                    'Skip for now',
                    style: AppTypography.label(
                        size: 13, color: AppColors.textFaint),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Option data ──────────────────────────────────────────────────────────────

class _Option {
  final String emoji;
  final String label;
  final String sub;
  final String relationId;
  const _Option({
    required this.emoji,
    required this.label,
    required this.sub,
    required this.relationId,
  });
}

// ─── Option card ──────────────────────────────────────────────────────────────

class _OptionCard extends StatefulWidget {
  final _Option option;
  final VoidCallback onTap;
  const _OptionCard({required this.option, required this.onTap});

  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        decoration: BoxDecoration(
          color: _pressed
              ? AppColors.ember.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _pressed
                ? AppColors.emberWarm.withValues(alpha: 0.50)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.option.emoji,
              style: const TextStyle(fontSize: 40),
            ),
            const SizedBox(height: 10),
            Text(
              widget.option.label,
              style: AppTypography.body(
                  size: 15, weight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                widget.option.sub,
                style: AppTypography.caption(size: 11.5),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
