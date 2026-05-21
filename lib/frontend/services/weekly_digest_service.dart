// ─── Weekly Digest Service ────────────────────────────────────────────────────
//
// Schedules a local notification every Sunday at 8 PM summarising the user's
// week with their most active diary contact.
//
// Native setup required (not done automatically by this file):
//
//   Android — android/app/src/main/AndroidManifest.xml, inside <manifest>:
//     <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
//     <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
//     <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
//     inside <application>:
//       <receiver android:exported="false"
//                 android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
//         <intent-filter>
//           <action android:name="android.intent.action.BOOT_COMPLETED"/>
//           <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
//         </intent-filter>
//       </receiver>
//
//   iOS — no extra setup; permission is requested at runtime.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../state/diary_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'notification_service.dart';

class WeeklyDigestService {
  WeeklyDigestService._();
  static final WeeklyDigestService instance = WeeklyDigestService._();

  // ── Constants ─────────────────────────────────────────────────────────────

  static const _channelId   = 'saanjh_weekly_digest';
  static const _channelName = 'Weekly Memory Digest';
  static const _notifId     = 100;

  static const _kAskedPerm  = 'weekly_digest_asked_perm';
  static const _kWeekKey    = 'weekly_digest_week'; // 'YYYY-Www'

  // ── Plugin ────────────────────────────────────────────────────────────────

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _pluginReady = false;

  Future<void> _ensurePlugin() async {
    if (_pluginReady) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestSoundPermission:  false,
      requestBadgePermission:  false,
      requestAlertPermission:  false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _pluginReady = true;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Call once from HomeScreen.initState() (via addPostFrameCallback).
  Future<void> init() async {
    if (!NotificationService.instance.enabled) return;
    await _ensurePlugin();
    await _maybeSchedule();
  }

  /// Show the in-app "Get a weekly memory digest?" soft-ask.
  /// Only shown once — on the first Sunday after install.
  Future<void> maybeShowPermissionAsk(BuildContext context) async {
    if (!NotificationService.instance.enabled) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAskedPerm) == true) return;

    // Only ask on Sundays (the day the digest would fire).
    if (DateTime.now().weekday != DateTime.sunday) return;

    await prefs.setBool(_kAskedPerm, true);
    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DigestPermissionSheet(
        onAccept: () async {
          Navigator.pop(context);
          await _requestPermissionAndSchedule();
        },
        onDecline: () => Navigator.pop(context),
      ),
    );
  }

  /// Called when the user toggles off notifications in Me screen.
  Future<void> setEnabled(bool value) async {
    if (!value) {
      await _ensurePlugin();
      await _plugin.cancel(_notifId);
    } else {
      await init();
    }
  }

  // ── Scheduling ────────────────────────────────────────────────────────────

  Future<void> _maybeSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    // Guard: don't re-schedule if already done this week.
    if (prefs.getString(_kWeekKey) == _currentWeekKey()) return;
    await _schedule(prefs);
  }

  Future<void> _requestPermissionAndSchedule() async {
    await _ensurePlugin();
    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    final prefs = await SharedPreferences.getInstance();
    await _schedule(prefs);
  }

  Future<void> _schedule(SharedPreferences prefs) async {
    final content = _digestContent();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription:
          'A warm weekly summary of your moments with loved ones',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // zonedSchedule + dayOfWeekAndTime → repeats every Sunday at 8 PM.
    await _plugin.zonedSchedule(
      _notifId,
      content.$1, // title
      content.$2, // body
      _nextSundayAt8pm(),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );

    await prefs.setString(_kWeekKey, _currentWeekKey());
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// ISO-ish week key: 'YYYY-Www' — resets every Monday.
  String _currentWeekKey() {
    final now = DateTime.now();
    final monday =
        now.subtract(Duration(days: now.weekday - 1));
    return '${monday.year}-W${monday.month.toString().padLeft(2, '0')}'
        '${monday.day.toString().padLeft(2, '0')}';
  }

  tz.TZDateTime _nextSundayAt8pm() {
    final now = tz.TZDateTime.now(tz.local);
    var daysToSunday = DateTime.sunday - now.weekday;
    if (daysToSunday < 0) daysToSunday += 7;
    // If today is Sunday and it's already past 8 PM, add a week.
    if (daysToSunday == 0 && now.hour >= 20) daysToSunday = 7;

    return tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + daysToSunday,
      20, // 8 PM
      0,
      0,
    );
  }

  (String, String) _digestContent() {
    final ds = DiaryStore.instance;
    if (ds.diaries.isEmpty) {
      return (
        'Your week on Saanjh',
        'A quiet week. Who would you like to stay close to?',
      );
    }

    // Most active diary: highest streak, tie-break by entry count.
    final best = ds.diaries.reduce((a, b) {
      final sa = ds.streakDays(a.id);
      final sb = ds.streakDays(b.id);
      if (sa != sb) return sa > sb ? a : b;
      return ds.entriesFor(a.id).length >= ds.entriesFor(b.id).length ? a : b;
    });

    final streak = ds.streakDays(best.id);
    final noteCount = ds.entriesFor(best.id).length;
    final month = DateTime.now().month;
    final season = month >= 3 && month <= 5
        ? 'Spring'
        : month >= 6 && month <= 8
            ? 'Summer'
            : month >= 9 && month <= 11
                ? 'Autumn'
                : 'Winter';

    final streakPart = streak > 1 ? ' · $streak days in a row' : '';
    return (
      'Your week with ${best.displayName}',
      '$noteCount voice notes$streakPart · $season on your tree',
    );
  }
}

// ─── Permission ask sheet ─────────────────────────────────────────────────────

class _DigestPermissionSheet extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _DigestPermissionSheet({
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          28, 0, 28, MediaQuery.of(context).padding.bottom + 24),
      decoration: const BoxDecoration(
        color: AppColors.modalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.ember.withValues(alpha: 0.14),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 26, color: AppColors.emberWarm),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Get a weekly memory digest?',
            style: AppTypography.title(size: 22),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // Body
          Text(
            'Every Sunday evening, we\'ll send you a warm summary '
            'of your week — voice notes, streaks, and the season '
            'on your memory tree.',
            style: AppTypography.serifItalic(size: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Accept CTA
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onAccept();
            },
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppColors.emberGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'Yes, remind me every Sunday',
                  style: AppTypography.button(color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Decline
          TextButton(
            onPressed: onDecline,
            child: Text(
              'Not now',
              style: AppTypography.label(
                  size: 14, color: AppColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}
