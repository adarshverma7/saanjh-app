import 'package:flutter/material.dart';

import '../state/diary_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';

// ─── Unread count badge ───────────────────────────────────────────────────────

/// Circular counter badge shown over an avatar when unlistened entries exist.
/// Renders nothing when [count] is zero; the caller is responsible for
/// animating in/out so the badge never flashes on empty-to-empty transitions.
class SaanjhCountBadge extends StatelessWidget {
  final int count;

  const SaanjhCountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 9 ? '9+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.ember,
        borderRadius: BorderRadius.circular(9),
        // Ink border separates the badge from the avatar ring beneath it.
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
      child: Center(
        child: Text(
          label,
          style: AppTypography.label(
            size: 10,
            weight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─── Streak badge ─────────────────────────────────────────────────────────────

class SaanjhStreakBadge extends StatelessWidget {
  final int days;
  final bool atRisk;
  final bool sentToday;

  const SaanjhStreakBadge({
    super.key,
    required this.days,
    required this.atRisk,
    required this.sentToday,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (atRisk) {
      color = AppColors.destructive;
    } else if (sentToday) {
      // Use emberAccessible for small text to ensure WCAG AA contrast.
      color = AppColors.emberAccessible;
    } else {
      color = AppColors.emberAccessible.withValues(alpha: 0.70);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(atRisk ? '⏳' : '🔥',
              style: const TextStyle(fontSize: 10, height: 1.2)),
          const SizedBox(width: 3),
          Text(
            '$days',
            style: AppTypography.label(
                size: 11, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Flickered-you badge ──────────────────────────────────────────────────────

class SaanjhFlickeredYouBadge extends StatelessWidget {
  final String? timeLabel;

  const SaanjhFlickeredYouBadge({super.key, this.timeLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.emberWarm,
            boxShadow: AppShadows.dotGlow(intensity: 0.60, blur: 5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          timeLabel != null ? 'here at $timeLabel' : 'was here',
          style: AppTypography.label(
            size: 11,
            weight: FontWeight.w600,
            color: AppColors.emberBright,
          ),
        ),
      ],
    );
  }
}

// ─── Mutual badge ─────────────────────────────────────────────────────────────

class SaanjhMutualBadge extends StatelessWidget {
  const SaanjhMutualBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      '♥ both here',
      style: AppTypography.label(
        size: 11,
        weight: FontWeight.w600,
        color: const Color(0xFF7CD992),
      ),
    );
  }
}

// ─── Weather badge ────────────────────────────────────────────────────────────
// Only renders visible content for DiaryWeather.quiet; other states are silent.

class SaanjhWeatherBadge extends StatelessWidget {
  final DiaryWeather weather;

  const SaanjhWeatherBadge({super.key, required this.weather});

  @override
  Widget build(BuildContext context) {
    if (weather != DiaryWeather.quiet) return const SizedBox.shrink();
    return Text(
      '🌧 Quiet lately · say something?',
      style: AppTypography.serifItalic(
          size: 11, color: AppColors.textFaint),
    );
  }
}
