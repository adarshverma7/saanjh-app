import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';

enum SaanjhNotificationType {
  listenerReceipt,
  flickerReceived,
  mutualFlicker,
  streakAtRisk,
  streakBroke,
  milestone,
  onThisDay,
  occasion,
}

/// In-app notification banner — slides down from the top, auto-dismisses
/// after 3 s, tappable to navigate to a diary thread.
///
/// Usage via GlobalKey:
///   final _key = GlobalKey&lt;NotificationBannerState&gt;();
///   ...
///   NotificationBanner(key: _key)
///   ...
///   _key.currentState?.show(message, diaryId, type);
class NotificationBanner extends StatefulWidget {
  const NotificationBanner({super.key});

  @override
  State<NotificationBanner> createState() => NotificationBannerState();
}

class NotificationBannerState extends State<NotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  String? _message;
  String? _diaryId;
  SaanjhNotificationType _type = SaanjhNotificationType.listenerReceipt;
  Timer? _timer;
  // Optional overrides — take priority over type-derived routing.
  String? _overrideRoute;
  Map<String, dynamic>? _overrideExtra;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.medium);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AppMotion.easeSpring));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> show(
    String message,
    String? diaryId,
    SaanjhNotificationType type, {
    String? overrideRoute,
    Map<String, dynamic>? overrideExtra,
  }) async {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _message = message;
        _diaryId = diaryId;
        _type = type;
        _overrideRoute = overrideRoute;
        _overrideExtra = overrideExtra;
      });
    }
    await _ctrl.forward(from: 0);
    _timer = Timer(
      const Duration(milliseconds: 3000),
      _dismiss,
    );
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    await _ctrl.reverse();
    if (mounted) setState(() => _message = null);
  }

  Color get _accent {
    switch (_type) {
      case SaanjhNotificationType.listenerReceipt:
      case SaanjhNotificationType.mutualFlicker:
        return const Color(0xFF7CD992); // ♥ green
      case SaanjhNotificationType.flickerReceived:
        return AppColors.emberWarm; // amber dot
      case SaanjhNotificationType.streakAtRisk:
        return AppColors.destructive; // red urgency
      case SaanjhNotificationType.streakBroke:
        return const Color(0xFFFFB340); // soft amber warmth
      case SaanjhNotificationType.milestone:
        return const Color(0xFFFFD60A); // golden
      case SaanjhNotificationType.onThisDay:
        return const Color(0xFFD4A853); // sepia gold
      case SaanjhNotificationType.occasion:
        return const Color(0xFFFF9500); // warm orange
    }
  }

  // Route to push when the banner is tapped.
  String get _targetRoute {
    switch (_type) {
      case SaanjhNotificationType.flickerReceived:
      case SaanjhNotificationType.mutualFlicker:
        return AppRoutes.flicker;
      case SaanjhNotificationType.onThisDay:
        return AppRoutes.onThisDay;
      case SaanjhNotificationType.listenerReceipt:
      case SaanjhNotificationType.streakAtRisk:
      case SaanjhNotificationType.streakBroke:
      case SaanjhNotificationType.milestone:
      case SaanjhNotificationType.occasion:
        return AppRoutes.diaryThread;
    }
  }

  Widget _buildIconArea(Color color) {
    // mutualFlicker shows ♥♥ (two offset hearts).
    if (_type == SaanjhNotificationType.mutualFlicker) {
      return SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          children: [
            Positioned(
              left: 6,
              top: 9,
              child: Icon(Icons.favorite_rounded, size: 13, color: color),
            ),
            Positioned(
              left: 14,
              top: 9,
              child: Icon(Icons.favorite_rounded, size: 13, color: color),
            ),
          ],
        ),
      );
    }

    final IconData icon;
    final double size;
    switch (_type) {
      case SaanjhNotificationType.listenerReceipt:
        icon = Icons.favorite_rounded;
        size = 17;
        break;
      case SaanjhNotificationType.flickerReceived:
        icon = Icons.circle;
        size = 12;
        break;
      case SaanjhNotificationType.streakAtRisk:
        icon = Icons.timer_rounded;
        size = 17;
        break;
      case SaanjhNotificationType.streakBroke:
        icon = Icons.heart_broken_rounded;
        size = 17;
        break;
      case SaanjhNotificationType.milestone:
        icon = Icons.local_fire_department_rounded;
        size = 17;
        break;
      case SaanjhNotificationType.onThisDay:
        icon = Icons.calendar_today_rounded;
        size = 17;
        break;
      case SaanjhNotificationType.occasion:
        icon = Icons.celebration_rounded;
        size = 17;
        break;
      case SaanjhNotificationType.mutualFlicker:
        // Already handled above via early return.
        icon = Icons.favorite_rounded;
        size = 17;
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
      ),
      child: Icon(icon, size: size, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_message == null) return const SizedBox.shrink();

    final color = _accent;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: GestureDetector(
              onTap: () {
                _dismiss();
                if (!context.mounted) return;
                if (_overrideRoute != null) {
                  context.push(_overrideRoute!, extra: _overrideExtra);
                  return;
                }
                final Map<String, dynamic>? extra;
                switch (_type) {
                  case SaanjhNotificationType.flickerReceived:
                  case SaanjhNotificationType.mutualFlicker:
                    extra = _diaryId != null
                        ? {'targetDiaryId': _diaryId}
                        : null;
                    break;
                  case SaanjhNotificationType.onThisDay:
                    extra = null;
                    break;
                  default:
                    extra =
                        _diaryId != null ? {'diaryId': _diaryId} : null;
                }
                context.push(_targetRoute, extra: extra);
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0E16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: color.withValues(alpha: 0.28),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.52),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: color.withValues(alpha: 0.10),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildIconArea(color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _message!,
                        style: AppTypography.label(
                          size: 13,
                          color: AppColors.text,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _dismiss,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

