import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/flicker_api.dart';
import 'diary_store.dart';
import 'send_queue_store.dart';

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

  // Fired once per new incoming Flicker (dedup below).
  // HomeScreen sets this to show the full-screen emotional overlay.
  void Function(FlickerRecord record)? onFlickerReceived;

  // In-memory dedup: prevents re-firing within the same app session.
  final Set<String> _overlayFiredKeys = {};

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

  // Returns true when the error is a connectivity issue (worth retrying later).
  bool _isConnectivityError(Object e) {
    if (e is DioException) {
      return e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout;
    }
    return false;
  }

  void sendFlicker(String diaryId, String personName) {
    if (!windowOpen) return;
    // Optimistic: show immediately so the UI is responsive.
    _records.add(FlickerRecord(
      diaryId: diaryId,
      personName: personName,
      sentAt: DateTime.now(),
      isMine: true,
    ));
    notifyListeners();
    FlickerApi.instance.sendFlicker(diaryId).then((res) {
      if (res['is_mutual'] == true && !hasThemFlickeredToday(diaryId)) {
        _records.add(FlickerRecord(
          diaryId: diaryId,
          personName: personName,
          sentAt: DateTime.now(),
          isMine: false,
        ));
        notifyListeners();
      }
    }).catchError((e) {
      if (_isConnectivityError(e)) {
        // Queue for retry when connectivity returns (today only).
        SendQueueStore.instance.enqueueFlicker(diaryId);
      }
      // Non-connectivity errors: optimistic record stays (user sees it was sent).
    });
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
      final id   = diaryIds[i];
      final name = names[i];
      FlickerApi.instance.sendFlicker(id).then((res) {
        if (res['is_mutual'] == true && !hasThemFlickeredToday(id)) {
          _records.add(FlickerRecord(
            diaryId: id,
            personName: name,
            sentAt: DateTime.now(),
            isMine: false,
          ));
          notifyListeners();
        }
      }).catchError((e) {
        if (_isConnectivityError(e)) {
          SendQueueStore.instance.enqueueFlicker(id);
        }
      });
    }
    notifyListeners();
  }

  /// Loads today's flicker status from the backend for each connection.
  /// Call on screen init so the UI reflects the real server state.
  Future<void> loadFlickerStatus(List<DiaryContact> diaries) async {
    var changed = false;
    for (final diary in diaries) {
      try {
        final res = await FlickerApi.instance.getFlickerStatus(diary.id);
        final myAt = res['my_last_flicker_at'] as String?;
        final theirAt = res['partner_last_flicker_at'] as String?;

        if (myAt != null) {
          final dt = DateTime.tryParse(myAt);
          if (dt != null && _isToday(dt) && !hasMeFlickeredToday(diary.id)) {
            _records.add(FlickerRecord(
              diaryId: diary.id,
              personName: diary.name,
              sentAt: dt,
              isMine: true,
            ));
            changed = true;
          }
        }

        if (theirAt != null) {
          final dt = DateTime.tryParse(theirAt);
          if (dt != null && _isToday(dt) && !hasThemFlickeredToday(diary.id)) {
            final record = FlickerRecord(
              diaryId: diary.id,
              personName: diary.name,
              sentAt: dt,
              isMine: false,
            );
            _records.add(record);
            changed = true;

            // Fire the overlay callback once per diary per day.
            final now = DateTime.now();
            final dateStr = '${now.year}-'
                '${now.month.toString().padLeft(2, '0')}-'
                '${now.day.toString().padLeft(2, '0')}';
            final overlayKey = '${diary.id}:$dateStr';
            if (!_overlayFiredKeys.contains(overlayKey)) {
              final prefs = await SharedPreferences.getInstance();
              if (!(prefs.getBool('flicker_overlay_$overlayKey') ?? false)) {
                _overlayFiredKeys.add(overlayKey);
                prefs.setBool('flicker_overlay_$overlayKey', true).ignore();
                onFlickerReceived?.call(record);
              } else {
                _overlayFiredKeys.add(overlayKey);
              }
            }
          }
        }
      } catch (_) {
        // Ignore individual failures — partial data is fine.
      }
    }
    if (changed) notifyListeners();
  }

  // ── Dot opacity (dims as the pulse ages through the day) ──────────────────

  double dotOpacity(String diaryId) {
    final r = receivedToday(diaryId);
    if (r == null) return 0;
    final hours = r.age.inMinutes / 60.0;
    return (0.90 - hours * 0.06).clamp(0.18, 0.90);
  }
}
