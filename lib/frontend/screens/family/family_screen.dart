import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import '../../state/diary_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_typography.dart';
import '../../widgets/cta.dart';
import '../../widgets/saanjh_logo.dart';

class FamilyScreen extends StatelessWidget {
  final bool isEmbedded;
  const FamilyScreen({super.key, this.isEmbedded = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DiaryStore.instance,
      builder: (_, w) {
        final diaries = DiaryStore.instance.diaries;
        return Scaffold(
          backgroundColor: AppColors.ink,
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 18, 12),
                  child: Row(
                    children: [
                      if (!isEmbedded) ...[
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            context.pop();
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.05),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  width: 1),
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                size: 14, color: Color(0x9EF5EFE8)),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('FAMILY',
                                style: AppTypography.eyebrow(
                                    size: 10, color: AppColors.emberBright)),
                            Text('Your people',
                                style: AppTypography.title(size: 22)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.push(AppRoutes.discover);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: AppColors.emberGradient,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.ember.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_add_rounded,
                                  size: 14, color: Colors.white),
                              const SizedBox(width: 6),
                              Text('Add',
                                  style: AppTypography.label(
                                      size: 13,
                                      weight: FontWeight.w600,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: diaries.isEmpty
                    ? _EmptyFamily(onDiscover: () => context.push(AppRoutes.discover))
                    : ListView(
                        padding: EdgeInsets.fromLTRB(
                            20, 0, 20, MediaQuery.of(context).padding.bottom + 20),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _SectionLabel('YOUR DIARY CONNECTIONS'),
                          const SizedBox(height: 10),
                          for (final d in diaries) _FamilyCard(contact: d),
                          const SizedBox(height: 24),
                          CtaGhost(
                            label: 'Find more people on Saanjh',
                            onPressed: () => context.push(AppRoutes.discover),
                          ),
                          const SizedBox(height: 12),
                          CtaGhost(
                            label: 'Create a family group',
                            onPressed: () => context.push(AppRoutes.createGroup),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyFamily extends StatelessWidget {
  final VoidCallback onDiscover;
  const _EmptyFamily({required this.onDiscover});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SaanjhLogo(size: 60),
            const SizedBox(height: 24),
            Text(
              'No connections yet.',
              style: AppTypography.title(size: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Find people from your contacts who are already on Saanjh, or invite someone new.',
              style: AppTypography.serifItalic(size: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onDiscover();
              },
              child: Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  gradient: AppColors.emberGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ember.withValues(alpha: 0.42),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Center(
                  child: Text('Discover people',
                      style: AppTypography.button(color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(label,
          style: AppTypography.eyebrow(size: 10, color: AppColors.textFaint)),
    );
  }
}

class _FamilyCard extends StatefulWidget {
  final DiaryContact contact;
  const _FamilyCard({required this.contact});

  @override
  State<_FamilyCard> createState() => _FamilyCardState();
}

class _FamilyCardState extends State<_FamilyCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.contact;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(AppRoutes.diaryThread);
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.07), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    d.avatarColor,
                    d.avatarColor.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Text(d.initial,
                    style: AppTypography.title(size: 18).copyWith(
                        color: Colors.white, fontStyle: FontStyle.italic)),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name,
                      style: AppTypography.body(
                          size: 15, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${d.relation} · ${d.phone}',
                      style: AppTypography.label(
                          size: 12, color: AppColors.textFaint)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}
