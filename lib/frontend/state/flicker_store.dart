import 'package:flutter/material.dart';

class FlickerRecord {
  final String diaryId;
  final String personName;
  final DateTime sentAt;
  final bool isMine;

  const FlickerRecord({
    required this.diaryId,
    required this.personName,
    required this.sentAt,
    required this.isMine,
  });

  String get timeLabel {
    final h = sentAt.hour;
    final m = sentAt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $period';
  }

  Duration get age => DateTime.now().difference(sentAt);
}

/// The daily pulse window and urgency state.
enum FlickerWindowState {
  open,       // 6 AM – 9 PM  : normal
  lastChance, // 9 PM – 10 PM : window closing
  closed,     // 10 PM – 6 AM : window shut
}

/// Flicker is a daily "I am here" signal — separate from the voice/video streak.
/// Streak tracking lives in DiaryStore, tied to actual content sends.
class FlickerStore extends ChangeNotifier {
  FlickerStore._();
  static final FlickerStore instance = FlickerStore._();

  final List<FlickerRecord> _records = [];

  // ── Window timing ─────────────────────────────────────────────────────────

  /// Flicker is open all day — resets at midnight.
  /// Last chance is the final hour (11 PM) to nudge before the day ends.
  FlickerWindowState get windowState {
    final h = DateTime.now().hour;
    if (h == 23) return FlickerWindowState.lastChance;
    return FlickerWindowState.open;
  }

  /// Always open — no time-gated window.
  bool get windowOpen => true;

  /// Time remaining in today (until midnight reset).
  Duration get timeUntilWindowCloses {
    final now = DateTime.now();
    final midnight =
        DateTime(now.year, now.month, now.day + 1, 0, 0);
    return midnight.difference(now);
  }

  /// Time until midnight — when the next pulse becomes available.
  Duration get timeUntilNextWindow {
    final now = DateTime.now();
    final midnight =
        DateTime(now.year, now.month, now.day + 1, 0, 0);
    return midnight.difference(now);
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  FlickerRecord? receivedToday(String diaryId) {
    try {
      return _records.lastWhere(
          (r) => r.diaryId == diaryId && !r.isMine && _isToday(r.sentAt));
    } catch (_) {
      return null;
    }
  }

  FlickerRecord? sentToday(String diaryId) {
    try {
      return _records.lastWhere(
          (r) => r.diaryId == diaryId && r.isMine && _isToday(r.sentAt));
    } catch (_) {
      return null;
    }
  }

  bool hasMeFlickeredToday(String diaryId) => sentToday(diaryId) != null;
  bool hasThemFlickeredToday(String diaryId) => receivedToday(diaryId) != null;
  bool isMutualToday(String diaryId) =>
      hasMeFlickeredToday(diaryId) && hasThemFlickeredToday(diaryId);

  // ── Actions ───────────────────────────────────────────────────────────────

  void sendFlicker(String diaryId, String personName) {
    if (!windowOpen) return;
    _records.add(FlickerRecord(
      diaryId: diaryId,
      personName: personName,
      sentAt: DateTime.now(),
      isMine: true,
    ));
    notifyListeners();
  }

  void sendFlickerToMany(List<String> diaryIds, List<String> names) {
    if (!windowOpen) return;
    final now = DateTime.now();
    for (var i = 0; i < diaryIds.length; i++) {
      _records.add(FlickerRecord(
        diaryId: diaryIds[i],
        personName: names[i],
        sentAt: now,
        isMine: true,
      ));
    }
    notifyListeners();
  }

  // ── Dot opacity (dims as the pulse ages through the day) ──────────────────

  double dotOpacity(String diaryId) {
    final r = receivedToday(diaryId);
    if (r == null) return 0;
    final hours = r.age.inMinutes / 60.0;
    return (0.90 - hours * 0.06).clamp(0.18, 0.90);
  }
}

