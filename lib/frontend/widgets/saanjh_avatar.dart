import 'package:flutter/material.dart';

import '../state/diary_store.dart';
import '../state/flicker_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';

class SaanjhAvatar extends StatelessWidget {
  final DiaryContact contact;
  final double size;
  /// Whether to show a pulse/streak ring. Ring state is derived internally.
  final bool showRing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showGroupBadge;
  final bool showSelectionOverlay;
  final bool isSelected;

  const SaanjhAvatar({
    super.key,
    required this.contact,
    this.size = 52,
    this.showRing = true,
    this.onTap,
    this.onLongPress,
    this.showGroupBadge = false,
    this.showSelectionOverlay = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([FlickerStore.instance, DiaryStore.instance]),
      builder: (_, _) {
        final ps = FlickerStore.instance;
        final ds = DiaryStore.instance;

        final received = ps.receivedToday(contact.id);
        final mePulsed = ps.hasMeFlickeredToday(contact.id);
        final mutual = received != null && mePulsed;
        final receivedNotSent = received != null && !mePulsed;
        final streakDays = ds.streakDays(contact.id);

        final Color ringColor;
        final double ringAlpha;
        if (!showRing) {
          ringColor = Colors.transparent;
          ringAlpha = 0.0;
        } else if (mutual) {
          ringColor = AppColors.successGreen;
          ringAlpha = 0.65;
        } else if (receivedNotSent) {
          ringColor = AppColors.emberWarm;
          ringAlpha = 0.82;
        } else if (streakDays > 0) {
          ringColor = AppColors.emberWarm;
          ringAlpha = 0.28;
        } else {
          ringColor = Colors.transparent;
          ringAlpha = 0.0;
        }

        final streakLabel = streakDays > 0 ? ' $streakDays day streak.' : '';
        final pulseLabel = mePulsed ? ' Pulsed you today.' : '';
        return Semantics(
          label: '${contact.displayName} avatar.$streakLabel$pulseLabel',
          button: onTap != null,
          child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Avatar circle
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      contact.avatarColor,
                      contact.avatarColor.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: ringAlpha > 0
                      ? Border.all(
                          color: ringColor.withValues(alpha: ringAlpha),
                          width: 2,
                        )
                      : null,
                  boxShadow: ringAlpha > 0
                      ? [
                          BoxShadow(
                            color:
                                ringColor.withValues(alpha: ringAlpha * 0.45),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    contact.initial,
                    style: AppTypography.title(size: size * 0.36).copyWith(
                      color: Colors.white,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),

              // Group badge
              if (contact.isGroup && showGroupBadge && !showSelectionOverlay)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: size * 0.35,
                    height: size * 0.35,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.ink,
                      border: Border.all(color: AppColors.ink, width: 1.5),
                    ),
                    child: Icon(Icons.group_rounded,
                        size: size * 0.20, color: AppColors.emberBright),
                  ),
                ),

              // Selection overlay
              if (showSelectionOverlay)
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? AppColors.ember.withValues(alpha: 0.88)
                          : Colors.black.withValues(alpha: 0.42),
                    ),
                    child: isSelected
                        ? Icon(Icons.check_rounded,
                            size: size * 0.38, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        ); // close Semantics
      },
    );
  }
}

