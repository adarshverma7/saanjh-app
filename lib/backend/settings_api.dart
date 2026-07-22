import 'package:dio/dio.dart';
import 'api_client.dart';

class SettingsApi {
  SettingsApi._();
  static final SettingsApi instance = SettingsApi._();

  Dio get _dio => ApiClient.instance.dio;

  /// GET /settings — language, timezone, and all notification preferences.
  Future<AppSettings> getSettings() async {
    final res = await _dio.get('/settings');
    return AppSettings.fromJson(res.data as Map<String, dynamic>);
  }

  /// PATCH /settings — partial update; only the keys present in [patch] change.
  /// Keys match the backend UpdateSettingsDto (snake_case), e.g.
  /// {'new_entry': false, 'occasion_reminders': true, 'language': 'hi'}.
  Future<AppSettings> updateSettings(Map<String, dynamic> patch) async {
    final res = await _dio.patch('/settings', data: patch);
    return AppSettings.fromJson(res.data as Map<String, dynamic>);
  }
}

class AppSettings {
  final String language;
  final String timezone;
  final bool newEntry;
  final bool flickerReceived;
  final bool streakReminder;
  final String streakReminderTime;
  final bool occasionReminders;
  final bool morningRitual;
  final String morningRitualTime;
  final String quietHoursStart;
  final String quietHoursEnd;

  const AppSettings({
    required this.language,
    required this.timezone,
    required this.newEntry,
    required this.flickerReceived,
    required this.streakReminder,
    required this.streakReminderTime,
    required this.occasionReminders,
    required this.morningRitual,
    required this.morningRitualTime,
    required this.quietHoursStart,
    required this.quietHoursEnd,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        language:            (j['language'] as String?) ?? 'en',
        timezone:            (j['timezone'] as String?) ?? 'Asia/Kolkata',
        newEntry:            (j['new_entry'] as bool?) ?? true,
        flickerReceived:     (j['flicker_received'] as bool?) ?? true,
        streakReminder:      (j['streak_reminder'] as bool?) ?? true,
        streakReminderTime:  (j['streak_reminder_time'] as String?) ?? '20:00:00',
        occasionReminders:   (j['occasion_reminders'] as bool?) ?? true,
        morningRitual:       (j['morning_ritual'] as bool?) ?? true,
        morningRitualTime:   (j['morning_ritual_time'] as String?) ?? '08:00:00',
        quietHoursStart:     (j['quiet_hours_start'] as String?) ?? '22:00:00',
        quietHoursEnd:       (j['quiet_hours_end'] as String?) ?? '07:00:00',
      );
}
