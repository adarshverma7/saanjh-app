import 'dart:convert';

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
  FlickerStore._() {
    // Restore today's records from local cache immediately on startup so that
    // FlickerScreen shows the correct "already sent" state before the network
    // call returns.  SharedPreferences is fast local I/O — typically < 5 ms.
    _loadCachedRecords().ignore();
  }
  static final FlickerStore instance = FlickerStore._();

  final List<FlickerRecord> _records = [];

  // Fired once per new incoming Flicker (dedup below).
  // HomeScreen sets this to show the full-screen emotional overlay.
  void Function(FlickerRecord record)? onFlickerReceived;

  // In-memory dedup: prevents re-firing within the same app session.
  final Set<String> _overlayFiredKeys = {};

  // ── Today's record cache (SharedPreferences) ──────────────────────────────
  // Persists sent/received records across app restarts so the "already sent"
  // state is immediately correct without waiting for a network round-trip.
  // Format: JSON array of {diaryId, name, at (ISO-8601), mine (bool)}.
  // Only today's entries are retained; yesterday's are pruned on each write.

  static const _kRecordsCache = 'flicker_records_v1';

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  bool _isDateToday(DateTime dt) {
    final t = _todayStr();
    final ds = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    return ds == t;
  }

  // Loads today's cached records into _records on startup.
  Future<void> _loadCachedRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRecordsCache);
    if (raw == null) return;
    bool changed = false;
    try {
      for (final item in jsonDecode(raw) as List<dynamic>) {
        final at = DateTime.tryParse(item['at'] as String? ?? '');
        if (at == null || !_isDateToday(at)) continue;
        final id   = item['diaryId'] as String? ?? '';
        final name = item['name']    as String? ?? '';
        final mine = item['mine']    as bool?   ?? false;
        if (id.isEmpty) continue;
        if (mine ? hasMeFlickeredToday(id) : hasThemFlickeredToday(id)) continue;
        _records.add(FlickerRecord(diaryId: id, personName: name, sentAt: at, isMine: mine));
        changed = true;
      }
    } catch (_) {}
    if (changed) notifyListeners();
  }

  // Persists a newly-added record; prunes entries not from today.
  Future<void> _persistRecord(FlickerRecord r) async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> list = [];
    final raw = prefs.getString(_kRecordsCache);
    if (raw != null) {
      try {
        list = (jsonDecode(raw) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((m) {
              final at = DateTime.tryParse(m['at'] as String? ?? '');
              return at != null && _isDateToday(at);
            })
            .toList();
      } catch (_) {}
    }
    final alreadyIn = list.any((m) => m['diaryId'] == r.diaryId && m['mine'] == r.isMine);
    if (!alreadyIn) {
      list.add({
        'diaryId': r.diaryId,
        'name': r.personName,
        'at': r.sentAt.toIso8601String(),
        'mine': r.isMine,
      });
      prefs.setString(_kRecordsCache, jsonEncode(list)).ignore();
    }
  }

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
    final mine = FlickerRecord(
      diaryId: diaryId,
      personName: personName,
      sentAt: DateTime.now(),
      isMine: true,
    );
    _records.add(mine);
    _persistRecord(mine).ignore();
    notifyListeners();
    FlickerApi.instance.sendFlicker(diaryId).then((res) {
      // Add partner's record if they already flickered today (any time, not just 5-min window).
      final partnerAlreadyToday =
          res['partner_flickered_today'] == true || res['is_mutual'] == true;
      if (partnerAlreadyToday && !hasThemFlickeredToday(diaryId)) {
        final theirs = FlickerRecord(
          diaryId: diaryId,
          personName: personName,
          sentAt: DateTime.now(),
          isMine: false,
        );
        _records.add(theirs);
        _persistRecord(theirs).ignore();
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
      final mine = FlickerRecord(
        diaryId: diaryIds[i],
        personName: names[i],
        sentAt: now,
        isMine: true,
      );
      _records.add(mine);
      _persistRecord(mine).ignore();
      final id   = diaryIds[i];
      final name = names[i];
      FlickerApi.instance.sendFlicker(id).then((res) {
        final partnerAlreadyToday =
            res['partner_flickered_today'] == true || res['is_mutual'] == true;
        if (partnerAlreadyToday && !hasThemFlickeredToday(id)) {
          final theirs = FlickerRecord(
            diaryId: id,
            personName: name,
            sentAt: DateTime.now(),
            isMine: false,
          );
          _records.add(theirs);
          _persistRecord(theirs).ignore();
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
            final r = FlickerRecord(
              diaryId: diary.id,
              personName: diary.name,
              sentAt: dt,
              isMine: true,
            );
            _records.add(r);
            _persistRecord(r).ignore();
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
            _persistRecord(record).ignore();
            changed = true;
            await _maybeTriggerOverlay(record);
          }
        }
      } catch (_) {
        // Ignore individual failures — partial data is fine.
      }
    }
    if (changed) notifyListeners();
  }

  /// Called by HomeScreen when an SSE `flicker_received` event arrives.
  /// Adds the record instantly (no poll delay) and fires the overlay once.
  Future<void> handleSseFlickerReceived({
    required String diaryId,
    required String personName,
    required DateTime sentAt,
  }) async {
    if (!_isToday(sentAt)) return;
    if (hasThemFlickeredToday(diaryId)) return;
    final record = FlickerRecord(
      diaryId: diaryId,
      personName: personName,
      sentAt: sentAt,
      isMine: false,
    );
    _records.add(record);
    _persistRecord(record).ignore();
    notifyListeners();
    await _maybeTriggerOverlay(record);
  }

  // Fires the full-screen overlay exactly once per diary per calendar day.
  Future<void> _maybeTriggerOverlay(FlickerRecord record) async {
    final now = DateTime.now();
    final dateStr = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final overlayKey = '${record.diaryId}:$dateStr';
    if (_overlayFiredKeys.contains(overlayKey)) return;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('flicker_overlay_$overlayKey') ?? false)) {
      _overlayFiredKeys.add(overlayKey);
      prefs.setBool('flicker_overlay_$overlayKey', true).ignore();
      onFlickerReceived?.call(record);
    } else {
      _overlayFiredKeys.add(overlayKey);
    }
  }

  // ── Dot opacity (dims as the pulse ages through the day) ──────────────────

  double dotOpacity(String diaryId) {
    final r = receivedToday(diaryId);
    if (r == null) return 0;
    final hours = r.age.inMinutes / 60.0;
    return (0.90 - hours * 0.06).clamp(0.18, 0.90);
  }
}
