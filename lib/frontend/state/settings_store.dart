import 'package:flutter/foundation.dart';

import '../../backend/settings_api.dart';

/// Holds the server-synced notification preferences (backed by GET/PATCH
/// /settings). Toggles update optimistically and revert if the PATCH fails,
/// so the UI never drifts from the backend silently.
class SettingsStore extends ChangeNotifier {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  bool newEntry          = true;
  bool flickerReceived   = true;
  bool streakReminder    = true;
  bool occasionReminders = true;
  bool morningRitual     = true;
  String language        = 'en';

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Fetch the current settings from the backend. Best-effort — on failure the
  /// defaults above stay in place and [loaded] remains false so a later open
  /// can retry.
  Future<void> load() async {
    try {
      final s = await SettingsApi.instance.getSettings();
      newEntry          = s.newEntry;
      flickerReceived   = s.flickerReceived;
      streakReminder    = s.streakReminder;
      occasionReminders = s.occasionReminders;
      morningRitual     = s.morningRitual;
      language          = s.language;
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // Keep defaults; caller may retry on next open.
    }
  }

  Future<bool> setNewEntry(bool v) =>
      _sync('new_entry', v, () => newEntry, (x) => newEntry = x);

  Future<bool> setFlickerReceived(bool v) =>
      _sync('flicker_received', v, () => flickerReceived, (x) => flickerReceived = x);

  Future<bool> setStreakReminder(bool v) =>
      _sync('streak_reminder', v, () => streakReminder, (x) => streakReminder = x);

  Future<bool> setOccasionReminders(bool v) =>
      _sync('occasion_reminders', v, () => occasionReminders, (x) => occasionReminders = x);

  Future<bool> setMorningRitual(bool v) =>
      _sync('morning_ritual', v, () => morningRitual, (x) => morningRitual = x);

  /// Applies [value] optimistically, PATCHes the single [field], and rolls back
  /// if the request fails. Returns true on success.
  Future<bool> _sync(
    String field,
    bool value,
    bool Function() get,
    void Function(bool) set,
  ) async {
    final previous = get();
    if (previous == value) return true; // no-op
    set(value);
    notifyListeners();
    try {
      await SettingsApi.instance.updateSettings({field: value});
      return true;
    } catch (_) {
      set(previous);
      notifyListeners();
      return false;
    }
  }
}
