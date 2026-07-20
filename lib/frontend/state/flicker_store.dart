import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/flicker_api.dart';
import 'diary_store.dart';
import 'send_queue_store.dart';

// ── Public model ──────────────────────────────────────────────────────────────

class FlickerRecord {
  final String diaryId;
  final String personName;
  final DateTime sentAt;
  final bool isMine;
  final bool isMutual;

  const FlickerRecord({
    required this.diaryId,
    required this.personName,
    required this.sentAt,
    required this.isMine,
    this.isMutual = false,
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

enum FlickerWindowState {
  open,
  lastChance, // 11 PM–midnight: final nudge before daily reset
  closed,     // reserved — window is always open in current design
}

// ── Internal per-connection per-day state ─────────────────────────────────────
//
// Single atomic object per (connectionId × dateKey).
// Replaces the old List<FlickerRecord> which was vulnerable to:
//   • duplicate records from racing SSE + API-response paths
//   • fragmented SharedPreferences keys (flicker_records_v1, flicker_overlay_*)
//   • state inferred from event timing rather than computed from backend truth
//
// Serialised as one entry per connectionId in 'flicker_state_v2'.
// Only today's entries survive across restarts — yesterday's are silently dropped.

class _RelState {
  final String dateKey;      // 'yyyy-MM-dd' — authoritative daily-cycle key
  final String partnerName;  // cached display name for FlickerRecord construction
  final DateTime? mySentAt;
  final DateTime? theirSentAt;
  final bool receivedOverlayShown; // persisted: overlay fires exactly once per day
  final bool mutualOverlayShown;   // persisted: mutual overlay fires exactly once per day
  /// Server state version (max sent_at epoch ms of the pair). Lets a late SSE
  /// event be dropped instead of overwriting fresher server truth.
  final int version;
  /// True while an optimistic local send has not been confirmed by the server.
  /// Reconciliation leaves unconfirmed sends alone so a slow network doesn't
  /// make the user's own tap flicker off and back on.
  final bool pendingSend;

  const _RelState({
    required this.dateKey,
    this.partnerName = '',
    this.mySentAt,
    this.theirSentAt,
    this.receivedOverlayShown = false,
    this.mutualOverlayShown = false,
    this.version = 0,
    this.pendingSend = false,
  });

  bool get iSent    => mySentAt    != null;
  bool get theySent => theirSentAt != null;
  bool get isMutual => mySentAt    != null && theirSentAt != null;

  _RelState copyWith({
    String? partnerName,
    DateTime? mySentAt,
    DateTime? theirSentAt,
    bool? receivedOverlayShown,
    bool? mutualOverlayShown,
    int? version,
    bool? pendingSend,
  }) =>
      _RelState(
        dateKey:              dateKey,
        partnerName:          partnerName          ?? this.partnerName,
        mySentAt:             mySentAt             ?? this.mySentAt,
        theirSentAt:          theirSentAt          ?? this.theirSentAt,
        receivedOverlayShown: receivedOverlayShown ?? this.receivedOverlayShown,
        mutualOverlayShown:   mutualOverlayShown   ?? this.mutualOverlayShown,
        version:              version              ?? this.version,
        pendingSend:          pendingSend          ?? this.pendingSend,
      );

  /// Replaces the timestamps outright with server truth — including clearing
  /// them. copyWith cannot express "set this back to null", which is why a
  /// failed optimistic send used to stick around until the next day.
  _RelState withServerTimestamps({
    required DateTime? mySentAt,
    required DateTime? theirSentAt,
    required int version,
    String? partnerName,
  }) =>
      _RelState(
        dateKey:              dateKey,
        partnerName:          partnerName ?? this.partnerName,
        mySentAt:             mySentAt,
        theirSentAt:          theirSentAt,
        receivedOverlayShown: receivedOverlayShown,
        mutualOverlayShown:   mutualOverlayShown,
        version:              version,
        pendingSend:          false,
      );

  Map<String, dynamic> toJson() => {
        'dk': dateKey,
        if (partnerName.isNotEmpty) 'n':  partnerName,
        if (mySentAt    != null)    'ms': mySentAt!.toIso8601String(),
        if (theirSentAt != null)    'ts': theirSentAt!.toIso8601String(),
        if (receivedOverlayShown)   'ro': true,
        if (mutualOverlayShown)     'mo': true,
        if (version != 0)           'v':  version,
      };

  factory _RelState.fromJson(Map<String, dynamic> j) => _RelState(
        dateKey:     j['dk'] as String? ?? '',
        partnerName: j['n']  as String? ?? '',
        mySentAt:    j['ms'] != null ? DateTime.tryParse(j['ms'] as String) : null,
        theirSentAt: j['ts'] != null ? DateTime.tryParse(j['ts'] as String) : null,
        receivedOverlayShown: j['ro'] as bool? ?? false,
        mutualOverlayShown:   j['mo'] as bool? ?? false,
        version:     j['v'] as int? ?? 0,
      );
}

// ── FlickerStore ──────────────────────────────────────────────────────────────

/// Authoritative daily-presence state for all connections.
///
/// Design contract:
/// - Backend is truth; SSE is the fast path; 30-second poll is the recovery path.
/// - One atomic _RelState per connection per calendar day. No list of events.
/// - All state transitions are idempotent: re-applying any event is safe.
/// - Overlays fire exactly once per cycle regardless of restarts or duplicates.
/// - Single SharedPreferences key ('flicker_state_v2') — no key fragmentation.
/// - notifyListeners is debounced via microtask to batch concurrent transitions.
class FlickerStore extends ChangeNotifier {
  FlickerStore._() {
    // Restore today's state immediately from cache so UI is correct before the
    // first network round-trip returns. SharedPreferences is synchronous-ish
    // local I/O — typically resolves in < 5 ms.
    _load().ignore();
  }
  static final FlickerStore instance = FlickerStore._();

  // ── State ─────────────────────────────────────────────────────────────────

  final Map<String, _RelState> _rels = {};
  bool _pendingNotify = false;

  // HomeScreen sets this to show the full-screen emotional overlay.
  // Fired at most once per overlay type per connection per calendar day.
  void Function(FlickerRecord record)? onFlickerReceived;

  // ── Persistence ───────────────────────────────────────────────────────────

  static const _kStateKey = 'flicker_state_v2';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStateKey);
    if (raw == null) return;
    try {
      final today = _todayKey();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      bool changed = false;
      for (final e in map.entries) {
        final s = _RelState.fromJson(e.value as Map<String, dynamic>);
        if (s.dateKey == today) {
          _rels[e.key] = s;
          changed = true;
        }
        // States from previous days are silently discarded.
      }
      if (changed) {
        notifyListeners();
        // Callback is set by HomeScreen.initState() synchronously before this
        // Future resolves, so any overlay pending in the restored cache can fire
        // immediately here instead of waiting for the next network round-trip.
        _checkPendingOverlays();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final out = <String, dynamic>{};
    for (final e in _rels.entries) {
      if (e.value.dateKey == today) out[e.key] = e.value.toJson();
    }
    prefs.setString(_kStateKey, jsonEncode(out)).ignore();
  }

  // ── Daily cycle helpers ───────────────────────────────────────────────────

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  bool _isToday(DateTime dt) {
    final local = dt.toLocal();
    final n = DateTime.now();
    return local.year == n.year && local.month == n.month && local.day == n.day;
  }

  DateTime? _parseIfToday(String? raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    return _isToday(dt) ? dt.toLocal() : null;
  }

  // ── Atomic state machine ──────────────────────────────────────────────────

  // Returns today's state, or a fresh idle state if the day has changed.
  _RelState _base(String diaryId) {
    final today = _todayKey();
    final s = _rels[diaryId];
    return (s != null && s.dateKey == today) ? s : _RelState(dateKey: today);
  }

  // All mutations go through here. Dart's single-threaded event loop guarantees
  // that the read-modify-write is atomic within a synchronous block.
  void _transition(String diaryId, _RelState Function(_RelState) fn) {
    _rels[diaryId] = fn(_base(diaryId));
    _persist().ignore();
    _scheduleNotify();
  }

  // Batches all synchronous transitions in one event loop turn into a single
  // notifyListeners() call, preventing rebuild spam when multiple fields update.
  void _scheduleNotify() {
    if (_pendingNotify) return;
    _pendingNotify = true;
    Future.microtask(() {
      _pendingNotify = false;
      notifyListeners();
    });
  }

  // ── Window timing ─────────────────────────────────────────────────────────

  FlickerWindowState get windowState {
    final h = DateTime.now().hour;
    if (h == 23) return FlickerWindowState.lastChance;
    return FlickerWindowState.open;
  }

  bool get windowOpen => true;

  Duration get timeUntilWindowCloses {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1).difference(now);
  }

  Duration get timeUntilNextWindow => timeUntilWindowCloses;

  // ── Public queries (backward compatible) ──────────────────────────────────

  bool hasMeFlickeredToday(String diaryId)   => _base(diaryId).iSent;
  bool hasThemFlickeredToday(String diaryId) => _base(diaryId).theySent;
  bool isMutualToday(String diaryId)         => _base(diaryId).isMutual;

  FlickerRecord? sentToday(String diaryId) {
    final s = _base(diaryId);
    if (!s.iSent) return null;
    return FlickerRecord(
      diaryId: diaryId, personName: s.partnerName,
      sentAt: s.mySentAt!, isMine: true,
    );
  }

  FlickerRecord? receivedToday(String diaryId) {
    final s = _base(diaryId);
    if (!s.theySent) return null;
    return FlickerRecord(
      diaryId: diaryId, personName: s.partnerName,
      sentAt: s.theirSentAt!, isMine: false,
    );
  }

  double dotOpacity(String diaryId) {
    final s = _base(diaryId);
    if (s.theirSentAt == null) return 0;
    final hours = DateTime.now().difference(s.theirSentAt!).inMinutes / 60.0;
    return (0.90 - hours * 0.06).clamp(0.18, 0.90);
  }

  // ── Send actions ──────────────────────────────────────────────────────────

  void sendFlicker(String diaryId, String partnerName) {
    if (!windowOpen) return;
    // Optimistic: show it immediately, flagged pending so reconciliation won't
    // wipe it while the request is still in flight.
    // Idempotent: s.mySentAt ?? now preserves any existing timestamp.
    _transition(diaryId, (s) => s.copyWith(
      partnerName: partnerName,
      mySentAt: s.mySentAt ?? DateTime.now(),
      pendingSend: true,
    ));
    _confirmSend(diaryId, partnerName);
  }

  void sendFlickerToMany(List<String> diaryIds, List<String> names) {
    if (!windowOpen) return;
    final now = DateTime.now();
    for (var i = 0; i < diaryIds.length; i++) {
      final id   = diaryIds[i];
      final name = names[i];
      _transition(id, (s) => s.copyWith(
        partnerName: name,
        mySentAt: s.mySentAt ?? now,
        pendingSend: true,
      ));
      _confirmSend(id, name);
    }
  }

  /// Sends to the server and adopts the confirmed state it returns, so the
  /// optimistic guess is always replaced by the same truth the partner sees.
  void _confirmSend(String diaryId, String partnerName) {
    FlickerApi.instance.sendFlicker(diaryId).then((res) {
      final isMutual = res['is_mutual'] == true;
      final partnerAlreadyToday =
          res['partner_flickered_today'] == true || isMutual;

      _transition(diaryId, (s) => s.copyWith(pendingSend: false));

      // Server confirmed the partner's side — apply it even if the SSE event
      // never arrived (offline, backgrounded, dropped stream).
      if (partnerAlreadyToday) {
        _applyTheirFlicker(diaryId, partnerName, DateTime.now());
      }
      if (isMutual) {
        _maybeMutualOverlay(diaryId, partnerName, DateTime.now());
      }
    }).catchError((Object e) {
      if (_isConnectivityError(e)) {
        // Queued for retry — keep the optimistic state pending so it survives
        // reconciliation until the queued send actually lands.
        SendQueueStore.instance.enqueueFlicker(diaryId);
      } else {
        // The server rejected it (rate limit, dead connection). Clear pending
        // so the next reconcile can correct the UI instead of showing a
        // flicker the partner will never see.
        _transition(diaryId, (s) => s.copyWith(pendingSend: false));
      }
    });
  }

  // ── State rehydration ─────────────────────────────────────────────────────

  /// Fetches authoritative state from backend for every connection in parallel.
  /// Call on: startup (after connections load), app foreground, SSE reconnect.
  Future<void> loadFlickerStatus(List<DiaryContact> diaries) async {
    if (diaries.isEmpty) return;
    // Parallel: old code was sequential (N × round-trip latency).
    await Future.wait(diaries.map(_loadOneStatus).toList(), eagerError: false);
    // Fire any overlays that _loadOneStatus revealed but _applyTheirFlicker
    // couldn't trigger because theirSentAt was already in the restored cache
    // (state transition diff = no-op → _maybeReceivedOverlay not reached).
    _checkPendingOverlays();
  }

  Future<void> _loadOneStatus(DiaryContact diary) async {
    try {
      final res = await FlickerApi.instance.getFlickerStatus(diary.id);
      applyServerState(
        diaryId: diary.id,
        partnerName: diary.name,
        mySentAtRaw: res['my_last_flicker_at'] as String?,
        theirSentAtRaw: res['partner_last_flicker_at'] as String?,
      );
    } catch (_) {
      // Partial failures are fine — other connections still update.
    }
  }

  // ── Authoritative reconciliation ──────────────────────────────────────────

  /// Adopts the backend's canonical state for one connection wholesale.
  ///
  /// This is the only path that may *clear* a timestamp, which is what keeps
  /// the two devices identical: previously the client could only ever add
  /// flickers, so an optimistic send that never reached the server (or state
  /// left over from another device) stayed on screen for the rest of the day
  /// while the partner saw nothing.
  ///
  /// Both SSE `flicker_state` and the status poll funnel through here, so a
  /// poll can never disagree with an event — the server derives both from one
  /// computation.
  void applyServerState({
    required String diaryId,
    required String partnerName,
    required String? mySentAtRaw,
    required String? theirSentAtRaw,
    int version = 0,
  }) {
    final before = _base(diaryId);

    // Drop events that raced past fresher state we already hold.
    if (version != 0 && before.version > version) return;

    final myAt = _parseIfToday(mySentAtRaw);
    final theirAt = _parseIfToday(theirSentAtRaw);

    // An in-flight local send is not yet visible to the server; keep showing it
    // rather than letting the user's own tap blink off and back on.
    final keepOptimistic = before.pendingSend && myAt == null;

    _transition(diaryId, (s) => s.withServerTimestamps(
      partnerName: partnerName.isNotEmpty ? partnerName : null,
      mySentAt: keepOptimistic ? s.mySentAt : myAt,
      theirSentAt: theirAt,
      version: version != 0 ? version : s.version,
    ));

    if (keepOptimistic) {
      _transition(diaryId, (s) => s.copyWith(pendingSend: true));
    }

    final after = _base(diaryId);

    // Overlays fire on real transitions only, so reconciliation is silent when
    // nothing actually changed.
    if (!before.isMutual && after.isMutual) {
      _maybeMutualOverlay(diaryId, partnerName, after.theirSentAt ?? DateTime.now());
    } else if (!before.theySent && after.theySent) {
      _maybeReceivedOverlay(diaryId, partnerName, after.theirSentAt!);
    }
  }

  /// Called by HomeScreen when the canonical SSE `flicker_state` arrives.
  /// Both users receive this from the same server-side computation, so mutual
  /// appears on both devices at the same moment.
  void handleSseFlickerState({
    required String diaryId,
    required String partnerName,
    required Map<String, dynamic> event,
  }) {
    applyServerState(
      diaryId: diaryId,
      partnerName: partnerName,
      mySentAtRaw: event['my_last_flicker_at'] as String?,
      theirSentAtRaw: event['partner_last_flicker_at'] as String?,
      version: (event['version'] as num?)?.toInt() ?? 0,
    );
  }

  // ── SSE fast-path handlers ────────────────────────────────────────────────

  /// Called by HomeScreen when SSE `flicker_received` arrives.
  Future<void> handleSseFlickerReceived({
    required String diaryId,
    required String personName,
    required DateTime sentAt,
  }) async {
    if (!_isToday(sentAt)) return;
    _applyTheirFlicker(diaryId, personName, sentAt);
  }

  /// Called by HomeScreen when SSE `mutual_reveal` arrives.
  /// First-sender path: they never got a `flicker_received` event, so this is
  /// where they learn the partner flickered back.
  Future<void> handleSseMutualReveal({
    required String diaryId,
    required String personName,
    required DateTime sentAt,
  }) async {
    if (!_isToday(sentAt)) return;
    _applyTheirFlicker(diaryId, personName, sentAt);
    // Explicit safety net: fires mutual overlay even when theirSentAt was already
    // set (second-sender path, flicker_received arrived earlier) but the mutual
    // overlay hasn't shown yet.
    _maybeMutualOverlay(diaryId, personName, sentAt);
  }

  // ── Overlay logic (idempotent) ────────────────────────────────────────────

  // Applies the partner's flicker and fires the appropriate overlay exactly once.
  //
  // Idempotency: theirSentAt is only set when null (s.theirSentAt ?? sentAt).
  // Overlay decisions are based on the state diff (before vs after), so
  // re-applying the same event is always a no-op.
  void _applyTheirFlicker(String diaryId, String name, DateTime sentAt) {
    final before = _base(diaryId);

    _transition(diaryId, (s) => s.copyWith(
      partnerName: name,
      theirSentAt: s.theirSentAt ?? sentAt, // idempotent: preserve earlier timestamp
    ));

    final after = _base(diaryId);

    // Fire overlay only on state transitions — not on re-applications.
    if (!before.isMutual && after.isMutual) {
      _maybeMutualOverlay(diaryId, name, sentAt);
    } else if (!before.theySent && after.theySent) {
      _maybeReceivedOverlay(diaryId, name, sentAt);
    }
  }

  // Fires the "they flickered" overlay exactly once per day.
  // Persisted: survives restarts and reconnects.
  // Guard: if callback is absent, leaves receivedOverlayShown=false so
  // _checkPendingOverlays() can retry once the callback is wired up.
  void _maybeReceivedOverlay(String diaryId, String name, DateTime sentAt) {
    if (_base(diaryId).receivedOverlayShown) return;
    if (onFlickerReceived == null) return; // retry via _checkPendingOverlays
    _transition(diaryId, (cur) => cur.copyWith(receivedOverlayShown: true));
    onFlickerReceived!.call(FlickerRecord(
      diaryId: diaryId, personName: name, sentAt: sentAt, isMine: false,
    ));
  }

  // Fires the "you're both here" overlay exactly once per day.
  // Uses a separate key from received overlay — both can fire independently.
  void _maybeMutualOverlay(String diaryId, String name, DateTime sentAt) {
    final s = _base(diaryId);
    if (!s.isMutual) return;
    if (s.mutualOverlayShown) return;
    if (onFlickerReceived == null) return; // retry via _checkPendingOverlays
    _transition(diaryId, (cur) => cur.copyWith(mutualOverlayShown: true));
    onFlickerReceived!.call(FlickerRecord(
      diaryId: diaryId, personName: name, sentAt: sentAt, isMine: false, isMutual: true,
    ));
  }

  // Scans all connections for pending (unshown) overlays and fires the first one.
  // Called after cache restore and after every loadFlickerStatus so overlays
  // that were pending while the callback was absent are never permanently lost.
  void _checkPendingOverlays() {
    if (onFlickerReceived == null) return;
    final today = _todayKey();
    for (final e in _rels.entries) {
      final s = e.value;
      if (s.dateKey != today) continue;
      // Mutual takes priority over received.
      if (s.isMutual && !s.mutualOverlayShown) {
        _maybeMutualOverlay(e.key, s.partnerName, s.theirSentAt ?? DateTime.now());
        return; // one overlay at a time
      }
      if (s.theySent && !s.receivedOverlayShown) {
        _maybeReceivedOverlay(e.key, s.partnerName, s.theirSentAt!);
        return;
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isConnectivityError(Object e) {
    if (e is DioException) {
      return e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout;
    }
    return false;
  }
}
