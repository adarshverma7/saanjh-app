import 'package:shared_preferences/shared_preferences.dart';

import '../state/diary_store.dart';
import '../state/personal_reflection_store.dart';

class OnThisDayService {
  OnThisDayService._();
  static final OnThisDayService instance = OnThisDayService._();

  static const _kCheckedKey  = 'on_this_day_checked';
  static const _kEnabledKey  = 'pref_on_this_day_on';

  // Set by load() — non-null when a personal reflection matches today's month+day from last year.
  PersonalReflection? todayPersonalReflection;

  // ── Enabled flag — persisted in SharedPreferences ─────────────────────────
  bool _enabled = true;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, value);
    if (!value) {
      // Clear the cached banner immediately so the home banner disappears.
      DiaryStore.instance.cacheOnThisDayEntry(null);
    }
  }

  // Runs once per calendar day. Finds a matching entry and caches it on DiaryStore.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabledKey) ?? true;
    if (!_enabled) return;
    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final lastCheck = prefs.getString(_kCheckedKey);
    if (lastCheck == todayKey) return;
    await prefs.setString(_kCheckedKey, todayKey);
    DiaryStore.instance.cacheOnThisDayEntry(checkToday());
    // Also check personal reflections for a year-ago match.
    todayPersonalReflection =
        PersonalReflectionStore.instance.todaysMemory();
  }

  // Searches all diary entries for today's month+day, excluding current year.
  // Returns the most recent match.
  DiaryEntry? checkToday() {
    return matchesFor(DateTime.now().month, DateTime.now().day).firstOrNull;
  }

  // All entries matching a given month+day across all past years, newest first.
  List<DiaryEntry> matchesFor(int month, int day) {
    final now = DateTime.now();
    final results = <DiaryEntry>[];
    for (final diary in DiaryStore.instance.diaries) {
      for (final entry in DiaryStore.instance.entriesFor(diary.id)) {
        if (entry.createdAt.year == now.year) continue;
        if (entry.createdAt.month != month) continue;
        if (entry.createdAt.day != day) continue;
        results.add(entry);
      }
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  // All matches for today (any past year).
  List<DiaryEntry> allTodayMatches() =>
      matchesFor(DateTime.now().month, DateTime.now().day);

  String yearLabel(DiaryEntry entry) {
    final years = DateTime.now().year - entry.createdAt.year;
    return years == 1 ? '1 year ago' : '$years years ago';
  }

  String contactName(DiaryEntry entry) {
    try {
      return DiaryStore.instance.diaries
          .firstWhere((d) => d.id == entry.diaryId)
          .displayName;
    } catch (_) {
      return 'someone';
    }
  }
}
