import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/connections_api.dart';
import '../theme/app_colors.dart';

// ─── Relationship weather ─────────────────────────────────────────────────────

enum DiaryWeather { sunny, partlyCloudy, overcast, quiet, clearingUp }

// ─── DiaryEntry ───────────────────────────────────────────────────────────────

class DiaryEntry {
  final String id;
  final String diaryId;
  final bool isMine;
  final String type; // 'voice' | 'video' | 'text'
  final String path; // local file path (empty for text/remote entries)
  final String? content; // text body (only for type == 'text')
  final String? transcript;
  final String? prompt; // prompt card text if record was prompted
  final String? occasionTag; // e.g. '🪔 Diwali greeting'
  final DateTime createdAt;
  final int durationSeconds; // 0 when unknown / text
  final bool isExpired; // true when diary_expires_at has passed (>24h)
  DateTime? listenedAt; // set when recipient plays the note
  double? moodEnergy; // 0.0–1.0, derived from amplitude analysis
  final List<DiaryEntry> reactions; // voice reactions to this entry
  final String? parentEntryId; // set for reactions; null for top-level entries
  final bool isPending; // optimistic send — upload not yet confirmed
  final bool isFailed;  // upload failed but queued for retry
  final bool savedToMoments; // text-only: user explicitly saved to Memory Tree

  // Signed media URL delivered via SSE new_entry event. Valid for ~1 hour.
  // Non-null for voice/video entries received in real-time; null for polled entries.
  final String? cachedMediaUrl;
  final DateTime? urlExpiresAt; // when cachedMediaUrl becomes stale

  // Messaging-action state (mutable — updated in place via store methods,
  // synced from the server and over SSE).
  Map<String, List<String>> emojiReactions; // {emoji: [userId, ...]}
  String? caption;   // author-set text annotation; media itself is immutable
  bool isPinned;     // shared pin, either member can toggle
  String? forwardedFrom; // original entry id when forwarded

  DiaryEntry({
    required this.id,
    required this.diaryId,
    required this.isMine,
    required this.type,
    required this.path,
    this.content,
    this.transcript,
    this.prompt,
    this.occasionTag,
    required this.createdAt,
    this.durationSeconds = 0,
    this.isExpired = false,
    this.listenedAt,
    this.moodEnergy,
    List<DiaryEntry>? reactions,
    this.parentEntryId,
    this.isPending = false,
    this.isFailed = false,
    this.savedToMoments = false,
    this.cachedMediaUrl,
    this.urlExpiresAt,
    Map<String, List<String>>? emojiReactions,
    this.caption,
    this.isPinned = false,
    this.forwardedFrom,
  })  : reactions = reactions ?? [],
        emojiReactions = emojiReactions ?? {};

  /// Compact JSON for the on-device entry cache (offline-first open).
  /// Media paths are intentionally excluded — MediaCacheService owns files.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'd': diaryId,
        'm': isMine,
        't': type,
        if (content != null) 'c': content,
        if (transcript != null) 'tr': transcript,
        'at': createdAt.millisecondsSinceEpoch,
        'ds': durationSeconds,
        if (isExpired) 'ex': true,
        if (listenedAt != null) 'la': listenedAt!.millisecondsSinceEpoch,
        if (savedToMoments) 'sm': true,
        if (emojiReactions.isNotEmpty) 'er': emojiReactions,
        if (caption != null) 'cap': caption,
        if (isPinned) 'pin': true,
        if (forwardedFrom != null) 'ff': forwardedFrom,
      };

  static DiaryEntry fromCacheJson(Map<String, dynamic> j) => DiaryEntry(
        id: j['id'] as String,
        diaryId: j['d'] as String,
        isMine: j['m'] as bool? ?? false,
        type: j['t'] as String? ?? 'voice',
        path: '',
        content: j['c'] as String?,
        transcript: j['tr'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
        durationSeconds: j['ds'] as int? ?? 0,
        isExpired: j['ex'] as bool? ?? false,
        listenedAt: j['la'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['la'] as int)
            : null,
        savedToMoments: j['sm'] as bool? ?? false,
        emojiReactions: (j['er'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, (v as List).cast<String>())),
        caption: j['cap'] as String?,
        isPinned: j['pin'] as bool? ?? false,
        forwardedFrom: j['ff'] as String?,
      );

  /// Non-null overrides only — a field can't be reset to null via copyWith.
  DiaryEntry copyWith({
    String? id,
    String? path,
    String? content,
    String? transcript,
    bool? isPending,
    bool? isFailed,
    bool? savedToMoments,
    String? cachedMediaUrl,
    DateTime? urlExpiresAt,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      diaryId: diaryId,
      isMine: isMine,
      type: type,
      path: path ?? this.path,
      content: content ?? this.content,
      transcript: transcript ?? this.transcript,
      prompt: prompt,
      occasionTag: occasionTag,
      createdAt: createdAt,
      durationSeconds: durationSeconds,
      isExpired: isExpired,
      listenedAt: listenedAt,
      moodEnergy: moodEnergy,
      reactions: reactions,
      parentEntryId: parentEntryId,
      isPending: isPending ?? this.isPending,
      isFailed: isFailed ?? this.isFailed,
      savedToMoments: savedToMoments ?? this.savedToMoments,
      cachedMediaUrl: cachedMediaUrl ?? this.cachedMediaUrl,
      urlExpiresAt: urlExpiresAt ?? this.urlExpiresAt,
      emojiReactions: emojiReactions,
      caption: caption,
      isPinned: isPinned,
      forwardedFrom: forwardedFrom,
    );
  }
}

// ─── DiaryContact ─────────────────────────────────────────────────────────────

class DiaryContact {
  final String id;
  final String name;
  final String relation; // freeform user-set label — not system-imposed
  final String phone;
  final String initial;
  final Color _baseAvatarColor; // underlying colour; overridden by avatarColorIndex
  final int avatarColorIndex; // -1 = use _baseAvatarColor; 0–7 = avatarPalette
  final bool isGroup;
  final List<DiaryContact> members; // group members (empty for 1:1 diaries)
  final String? elderMemberId; // designated Elder in the group
  final String lastSnippet;
  final String lastTime;
  final String customLabel; // user-set display name override (e.g. "Papa")
  final String? profileVoiceNotePath; // path to recorded introduction note
  final String? partnerUserId; // partner's user id — links stories to this diary

  // ── 8-colour user-selectable palette ──────────────────────────────────────

  static const List<Color> avatarPalette = [
    Color(0xFFFF9500), // Amber
    Color(0xFFFF6B00), // Ember
    Color(0xFFFF6B8A), // Rose
    AppColors.violet, // Purple
    AppColors.successGreen, // Green
    AppColors.azure, // Blue
    Color(0xFF5AC8FA), // Teal
    Color(0xFFFFD60A), // Gold
  ];

  // ── Computed colour — palette wins if index is valid ──────────────────────

  Color get avatarColor =>
      avatarColorIndex >= 0 && avatarColorIndex < avatarPalette.length
          ? avatarPalette[avatarColorIndex]
          : _baseAvatarColor;

  // ── Display name — custom label > name > phone ────────────────────────────

  String get displayName {
    if (customLabel.isNotEmpty) return customLabel;
    if (name.isNotEmpty) return name;
    return phone;
  }

  const DiaryContact({
    required this.id,
    required this.name,
    required this.relation,
    required this.phone,
    required this.initial,
    required Color avatarColor,
    this.avatarColorIndex = -1,
    this.isGroup = false,
    this.members = const [],
    this.elderMemberId,
    this.lastSnippet = '🎙 Tap to send your first voice note',
    this.lastTime = 'Now',
    this.customLabel = '',
    this.profileVoiceNotePath,
    this.partnerUserId,
  }) : _baseAvatarColor = avatarColor;

  DiaryContact copyWith({
    String? lastSnippet,
    String? lastTime,
    String? customLabel,
    int? avatarColorIndex,
    String? profileVoiceNotePath,
    List<DiaryContact>? members,
    String? elderMemberId,
    String? partnerUserId,
  }) {
    return DiaryContact(
      id: id,
      name: name,
      relation: relation,
      phone: phone,
      initial: initial,
      avatarColor: _baseAvatarColor,
      avatarColorIndex: avatarColorIndex ?? this.avatarColorIndex,
      isGroup: isGroup,
      members: members ?? this.members,
      elderMemberId: elderMemberId ?? this.elderMemberId,
      lastSnippet: lastSnippet ?? this.lastSnippet,
      lastTime: lastTime ?? this.lastTime,
      customLabel: customLabel ?? this.customLabel,
      profileVoiceNotePath:
          profileVoiceNotePath ?? this.profileVoiceNotePath,
      partnerUserId: partnerUserId ?? this.partnerUserId,
    );
  }
}

// ─── DiaryStore ───────────────────────────────────────────────────────────────

class DiaryStore extends ChangeNotifier {
  DiaryStore._() {
    // Load cached contacts instantly so the first paint shows real data.
    loadCachedEntries();
    _loadCachedContacts().then((_) {
      if (_isLoading && _diaries.isNotEmpty) {
        _isLoading = false;
        notifyListeners();
      }
    });
    // Safety valve: clear loading state after 5s even if offline / API hangs.
    Future.delayed(const Duration(seconds: 5), () {
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
    });
  }
  static final DiaryStore instance = DiaryStore._();

  // ── Cache keys ────────────────────────────────────────────────────────────
  static const _kContactsCache = 'diary_store_contacts_v2';
  static const _kStreakCache   = 'diary_store_streaks_v2';

  // ── Loading state ─────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  // ── Diaries ───────────────────────────────────────────────────────────────

  final List<DiaryContact> _diaries = [];

  final Set<String> _pinned     = {};
  final Set<String> _muted      = {};
  final Set<String> _favourites = {};
  final Set<String> _locked     = {};
  final Set<String> _archived   = {};

  // ── Entries (voice/video notes per diary) ─────────────────────────────────

  final Map<String, List<DiaryEntry>> _entries = {};

  // ── Streak tracking (voice/video sends — not pulse) ───────────────────────

  final Map<String, int> _streakDays = {};
  final Map<String, DateTime?> _lastSentDate = {};

  // ── Event flags (read-once — cleared after reading) ───────────────────────

  final Map<String, bool> _streakJustBroke = {};
  final Map<String, bool> _justResumed     = {};
  final Map<String, int?> _milestoneReached = {};

  // Stores the streak value at the moment it broke (so UI can say "N-day streak paused").
  final Map<String, int> _brokeStreakPreviousDays = {};

  // ── Per-diary metadata ────────────────────────────────────────────────────

  final Map<String, Set<String>> _jarredEntries = {};
  final Map<String, String?> _occasionTag = {};

  // ── On This Day cache ─────────────────────────────────────────────────────
  // Set by OnThisDayService.load() once per day; drives the home banner.
  DiaryEntry? _onThisDayEntry;

  DiaryEntry? get onThisDayEntry => _onThisDayEntry;

  void cacheOnThisDayEntry(DiaryEntry? entry) {
    _onThisDayEntry = entry;
    if (entry != null) notifyListeners();
  }

  static const List<int> _milestones = [3, 7, 14, 30, 60, 100, 365];

  // ── Listener's receipt signal ─────────────────────────────────────────────
  // Fired once per entry when a sent note (isMine: true) first gets listenedAt.
  // UI layer wires this up to show an in-app banner.
  void Function(String entryId, String diaryId)? onListenedReceipt;

  // ── Date helpers ──────────────────────────────────────────────────────────

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // STREAK QUERIES
  // ═════════════════════════════════════════════════════════════════════════

  int streakDays(String id) => _streakDays[id] ?? 0;

  bool hasSentToday(String id) {
    final last = _lastSentDate[id];
    return last != null && _isToday(last);
  }

  /// True when streak > 0, not sent today, and yesterday was the last send.
  bool streakAtRisk(String id) {
    if (streakDays(id) == 0) return false;
    if (hasSentToday(id)) return false;
    final last = _lastSentDate[id];
    if (last == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(last.year, last.month, last.day);
    return lastDay == today.subtract(const Duration(days: 1));
  }

  /// Reads and clears the streak-just-broke flag. Returns true once per break.
  bool streakJustBroke(String id) {
    final v = _streakJustBroke.remove(id) ?? false;
    return v;
  }

  /// Non-destructive peek — true if the broke flag is set without clearing it.
  /// Use this in build methods; use streakJustBroke() only for explicit clear.
  bool hasBrokeStreak(String id) => _streakJustBroke[id] ?? false;

  /// The streak value before it broke — used by the break banner.
  int brokeStreakPreviousDays(String id) => _brokeStreakPreviousDays[id] ?? 0;

  /// Reads and clears the just-resumed flag. Returns true once after resuming.
  bool justResumed(String id) {
    final v = _justResumed.remove(id) ?? false;
    return v;
  }

  /// Non-destructive peek for justResumed.
  bool hasJustResumed(String id) => _justResumed[id] ?? false;

  /// Reads and clears the milestone flag. Returns the milestone value once.
  int? milestoneReached(String id) {
    final v = _milestoneReached.remove(id);
    return v;
  }

  void clearMilestone(String id) => _milestoneReached.remove(id);

  // Returns the ambient health signal for a diary relationship.
  // Uses hasJustResumed (non-destructive) so build methods don't consume the flag.
  DiaryWeather weatherState(String id) {
    if (hasSentToday(id) && streakDays(id) > 0) return DiaryWeather.sunny;
    if (streakAtRisk(id)) return DiaryWeather.partlyCloudy;
    if (hasJustResumed(id)) return DiaryWeather.clearingUp;
    final last = _lastSentDate[id];
    if (last == null) return DiaryWeather.overcast;
    final gap = DateTime.now().difference(last).inDays;
    if (gap >= 7) return DiaryWeather.quiet;
    if (gap >= 3) return DiaryWeather.overcast;
    return DiaryWeather.partlyCloudy;
  }

  // Emoji tree that grows with streak.
  String streakTree(String id) {
    final d = streakDays(id);
    if (d >= 90) return '🌸';
    if (d >= 60) return '🎋';
    if (d >= 30) return '🌲';
    if (d >= 7)  return '🌿';
    if (d >= 1)  return '🌱';
    return '🪨';
  }

  String streakLabel(String id) {
    final d = streakDays(id);
    if (d >= 90) return 'In full bloom';
    if (d >= 60) return 'Deep roots';
    if (d >= 30) return 'Growing strong';
    if (d >= 7)  return 'Taking root';
    if (d >= 1)  return 'Just planted';
    return 'Not started yet';
  }

  int get bestStreakDays {
    if (_diaries.isEmpty) return 0;
    return _diaries
        .map((d) => streakDays(d.id))
        .reduce((a, b) => a > b ? a : b);
  }

  /// Alias for bestStreakDays — used by Me screen stats.
  int get bestSendStreak => bestStreakDays;

  /// Call on app open to proactively detect streaks that broke overnight.
  void checkForBrokenStreaks() {
    bool changed = false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final d in _diaries) {
      final id = d.id;
      final days = _streakDays[id] ?? 0;
      if (days == 0) continue;
      if (hasSentToday(id)) continue;
      final last = _lastSentDate[id];
      if (last == null) continue;
      final lastDay = DateTime(last.year, last.month, last.day);
      final diff = today.difference(lastDay).inDays;
      if (diff >= 2 && !(_streakJustBroke[id] ?? false)) {
        _brokeStreakPreviousDays[id] = days;
        _streakJustBroke[id] = true;
        _streakDays[id] = 0;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ── Internal: record a voice/video send toward streak ─────────────────────

  void _recordSend(String id) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = _lastSentDate[id];
    final wasJustBroke = _streakJustBroke[id] ?? false;
    final previousStreak = _streakDays[id] ?? 0;

    if (last == null) {
      // First ever send.
      _streakDays[id] = 1;
    } else if (wasJustBroke) {
      // Sending after a detected break — fresh start.
      _streakDays[id] = 1;
      _streakJustBroke.remove(id);
      _brokeStreakPreviousDays.remove(id);
      _justResumed[id] = true;
    } else {
      final lastDay = DateTime(last.year, last.month, last.day);
      final diff = today.difference(lastDay).inDays;
      if (diff == 0) {
        // Already sent today — streak unchanged.
      } else if (diff == 1) {
        // Consecutive day — streak continues.
        _streakDays[id] = previousStreak + 1;
      } else {
        // Missed day(s) — break not yet detected proactively; handle inline.
        _streakJustBroke.remove(id);
        _justResumed[id] = true;
        _streakDays[id] = 1;
      }
    }

    _lastSentDate[id] = now;

    // Check milestones on any streak increase.
    final newStreak = _streakDays[id] ?? 0;
    if (newStreak > previousStreak && _milestones.contains(newStreak)) {
      _milestoneReached[id] = newStreak;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ENTRY QUERIES & MUTATIONS
  // ═════════════════════════════════════════════════════════════════════════

  List<DiaryEntry> entriesFor(String diaryId) =>
      List.unmodifiable(_entries[diaryId] ?? []);

  void addEntry(DiaryEntry entry) {
    _entries.putIfAbsent(entry.diaryId, () => []).add(entry);
    _schedulePersistEntries(entry.diaryId);
    notifyListeners();
  }

  void bulkAddEntries(List<DiaryEntry> entries) {
    for (final e in entries) {
      _entries.putIfAbsent(e.diaryId, () => []).add(e);
      _schedulePersistEntries(e.diaryId);
    }
    if (entries.isNotEmpty) notifyListeners();
  }

  // ── Entry cache (offline-first) ────────────────────────────────────────────
  // Completed entries are persisted per diary so a chat opens instantly from
  // disk; the backend is then consulted only for incremental changes.

  static const _kEntriesCachePrefix = 'entries_cache_v1_';
  static const _entriesCacheCap = 200; // newest N entries kept per diary
  final Set<String> _dirtyEntryDiaries = {};
  Timer? _persistDebounce;
  bool _entriesCacheLoaded = false;

  void _schedulePersistEntries(String diaryId) {
    _dirtyEntryDiaries.add(diaryId);
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 1), () async {
      final dirty = Set<String>.from(_dirtyEntryDiaries);
      _dirtyEntryDiaries.clear();
      try {
        final prefs = await SharedPreferences.getInstance();
        for (final id in dirty) {
          final list = (_entries[id] ?? [])
              .where((e) => !e.isPending && !e.isFailed)
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final tail = list.length > _entriesCacheCap
              ? list.sublist(list.length - _entriesCacheCap)
              : list;
          await prefs.setString('$_kEntriesCachePrefix$id',
              jsonEncode(tail.map((e) => e.toCacheJson()).toList()));
        }
      } catch (_) {/* cache write is best-effort */}
    });
  }

  void _persistAllDirtyNow() {
    for (final id in _entries.keys) {
      _schedulePersistEntries(id);
    }
  }

  /// Loads every diary's cached entries from disk. Called once at startup so
  /// threads render instantly; later backend syncs merge on top by id.
  Future<void> loadCachedEntries() async {
    if (_entriesCacheLoaded) return;
    _entriesCacheLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var restored = false;
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_kEntriesCachePrefix)) continue;
        final diaryId = key.substring(_kEntriesCachePrefix.length);
        if (_entries[diaryId]?.isNotEmpty == true) continue;
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final list = (jsonDecode(raw) as List)
            .map((j) => DiaryEntry.fromCacheJson(j as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          _entries[diaryId] = list;
          restored = true;
        }
      }
      if (restored) notifyListeners();
    } catch (_) {/* corrupt cache — server sync rebuilds it */}
  }

  /// Removes all cached entries (sign-out). Media files are cleared separately
  /// by MediaCacheService.clear().
  Future<void> clearEntryCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_kEntriesCachePrefix)) await prefs.remove(key);
      }
    } catch (_) {}
    _entries.clear();
    _entriesCacheLoaded = false;
  }

  void markListened(String entryId) {
    for (final list in _entries.values) {
      for (final e in list) {
        if (e.id == entryId) {
          final isFirstListen = e.listenedAt == null;
          e.listenedAt = DateTime.now();
          _schedulePersistEntries(e.diaryId);
          notifyListeners();
          // Fire receipt signal only for sent notes getting their first listen.
          if (isFirstListen && e.isMine) {
            onListenedReceipt?.call(entryId, e.diaryId);
          }
          return;
        }
      }
    }
  }

  void updateEntryTranscript(String entryId, String transcript) {
    // DiaryEntry.transcript is final; create a replacement entry.
    for (final diaryId in _entries.keys) {
      final list = _entries[diaryId]!;
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == entryId) {
          list[i] = list[i].copyWith(transcript: transcript);
          notifyListeners();
          return;
        }
      }
    }
  }

  void updateEntryMood(String entryId, double energy) {
    for (final list in _entries.values) {
      for (final e in list) {
        if (e.id == entryId) {
          e.moodEnergy = energy;
          notifyListeners();
          return;
        }
      }
    }
  }

  void addReaction(String parentEntryId, DiaryEntry reaction) {
    for (final list in _entries.values) {
      for (final e in list) {
        if (e.id == parentEntryId) {
          e.reactions.add(reaction);
          notifyListeners();
          return;
        }
      }
    }
  }

  void removeEntry(String entryId) {
    for (final list in _entries.values) {
      list.removeWhere((e) => e.id == entryId);
    }
    _persistAllDirtyNow();
    notifyListeners();
  }

  /// Formatted "9:30 AM" label for when an entry was listened to.
  String? listenedAtLabel(String entryId) {
    for (final list in _entries.values) {
      for (final e in list) {
        if (e.id == entryId && e.listenedAt != null) {
          final h = e.listenedAt!.hour;
          final m = e.listenedAt!.minute.toString().padLeft(2, '0');
          final period = h >= 12 ? 'PM' : 'AM';
          final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
          return '$h12:$m $period';
        }
      }
    }
    return null;
  }

  /// Groups entry IDs by "YYYY-MM" key for the Memory Tree month view.
  Map<String, List<String>> momentsByMonth(String diaryId) {
    final entries = _entries[diaryId] ?? [];
    final result = <String, List<String>>{};
    for (final e in entries) {
      final key =
          '${e.createdAt.year}-${e.createdAt.month.toString().padLeft(2, '0')}';
      result.putIfAbsent(key, () => []).add(e.id);
    }
    // Sort descending (most recent month first).
    final sorted = Map.fromEntries(
      result.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
    return sorted;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // MEMORY JAR
  // ═════════════════════════════════════════════════════════════════════════

  void jarEntry(String diaryId, String entryId) {
    _jarredEntries.putIfAbsent(diaryId, () => {}).add(entryId);
    notifyListeners();
  }

  void unjarEntry(String diaryId, String entryId) {
    _jarredEntries[diaryId]?.remove(entryId);
    notifyListeners();
  }

  bool isJarred(String diaryId, String entryId) =>
      _jarredEntries[diaryId]?.contains(entryId) ?? false;

  Set<String> jarredFor(String diaryId) =>
      Set.unmodifiable(_jarredEntries[diaryId] ?? {});

  // ═════════════════════════════════════════════════════════════════════════
  // OCCASION TAGS
  // ═════════════════════════════════════════════════════════════════════════

  void setOccasionTag(String id, String? tag) {
    _occasionTag[id] = tag;
    // No notifyListeners — occasion tag is set at send time, not displayed live.
  }

  String? occasionTag(String id) => _occasionTag[id];

  // ═════════════════════════════════════════════════════════════════════════
  // PERSONALISATION
  // ═════════════════════════════════════════════════════════════════════════

  void updateCustomLabel(String id, String label) {
    final idx = _diaries.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    _diaries[idx] = _diaries[idx].copyWith(customLabel: label);
    notifyListeners();
  }

  void updateAvatarColorIndex(String id, int index) {
    final idx = _diaries.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    _diaries[idx] = _diaries[idx].copyWith(avatarColorIndex: index);
    notifyListeners();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ANNIVERSARIES
  // ═════════════════════════════════════════════════════════════════════════

  /// Returns a map of diaryId → years for diaries whose first entry
  /// anniversary falls on today's date.
  Map<String, int> get diaryAnniversaries {
    final result = <String, int>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final diaryId in _entries.keys) {
      final list = _entries[diaryId];
      if (list == null || list.isEmpty) continue;
      final first = list.reduce(
          (a, b) => a.createdAt.isBefore(b.createdAt) ? a : b);
      final firstDay = DateTime(
          first.createdAt.year, first.createdAt.month, first.createdAt.day);
      final diff = today.difference(firstDay);
      if (first.createdAt.month == now.month &&
          first.createdAt.day == now.day &&
          diff.inDays >= 365) {
        result[diaryId] = diff.inDays ~/ 365;
      }
    }
    return result;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DIARY QUERIES
  // ═════════════════════════════════════════════════════════════════════════

  bool isPinned   (String id) => _pinned.contains(id);
  bool isMuted    (String id) => _muted.contains(id);
  bool isFavourite(String id) => _favourites.contains(id);
  bool isLocked   (String id) => _locked.contains(id);
  bool isArchived (String id) => _archived.contains(id);
  bool has        (String id) => _diaries.any((d) => d.id == id);
  bool hasPhone   (String phone) =>
      phone.isNotEmpty && _diaries.any((d) => d.phone == phone);

  DiaryContact? findByPhone(String phone) {
    try { return _diaries.firstWhere((d) => d.phone == phone); }
    catch (_) { return null; }
  }

  /// Visible diaries: archived hidden, pinned sorted first.
  List<DiaryContact> get diaries {
    final visible = _diaries.where((d) => !_archived.contains(d.id)).toList();
    final pinned  = visible.where((d) => _pinned.contains(d.id)).toList();
    final rest    = visible.where((d) => !_pinned.contains(d.id)).toList();
    return [...pinned, ...rest];
  }

  /// Archived diaries for the archived-chats screen.
  List<DiaryContact> get archived =>
      _diaries.where((d) => _archived.contains(d.id)).toList();

  // ═════════════════════════════════════════════════════════════════════════
  // MUTATIONS
  // ═════════════════════════════════════════════════════════════════════════

  /// Clears all in-memory state on logout so a fresh login starts clean.
  void reset() {
    _diaries.clear();
    _entries.clear();
    _pinned.clear();
    _muted.clear();
    _favourites.clear();
    _locked.clear();
    _archived.clear();
    _streakDays.clear();
    _lastSentDate.clear();
    _streakJustBroke.clear();
    _justResumed.clear();
    _milestoneReached.clear();
    _isLoading = true;
    notifyListeners();
    _clearPersistedContacts(); // wipe cache so next user starts fresh
  }

  /// Loads the user's connections from the backend and populates the store.
  /// Safe to call multiple times — skips contacts already present; refreshes
  /// streak data for ones that are already loaded (e.g. from cache).
  /// Always clears _isLoading when complete (success or error).
  Future<void> loadConnections() async {
    try {
      final connections = await ConnectionsApi.instance.getConnections();
      var changed = false;

      for (final c in connections) {
        if ((c['status'] as String?) == 'deleted') continue;
        final id = c['id'] as String? ?? '';
        if (id.isEmpty) continue;

        final partner = c['partner'] as Map<String, dynamic>? ?? {};
        final rawName = (c['connection_name'] as String?)?.trim() ?? '';
        final name = rawName.isNotEmpty
            ? rawName
            : (partner['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;

        final streak = c['streak_count'] as int? ?? 0;
        final lastAt = c['last_entry_at'] as String?;

        if (has(id)) {
          // Refresh streak from server even for contacts already in store.
          final prev = _streakDays[id] ?? 0;
          if (streak != prev) {
            _streakDays[id] = streak;
            if (lastAt != null) {
              final dt = DateTime.tryParse(lastAt);
              if (dt != null) _lastSentDate[id] = dt;
            }
            changed = true;
          }
          // Backfill partner user id on contacts restored from an older cache.
          final pid = partner['id'] as String?;
          if (pid != null) {
            final idx = _diaries.indexWhere((d) => d.id == id);
            if (idx >= 0 && _diaries[idx].partnerUserId == null) {
              _diaries[idx] = _diaries[idx].copyWith(partnerUserId: pid);
              changed = true;
            }
          }
          continue;
        }

        final initial = name[0].toUpperCase();
        final hash = name.codeUnits.fold(0, (a, b) => a + b);
        final color = DiaryContact.avatarPalette[hash % DiaryContact.avatarPalette.length];

        _diaries.add(DiaryContact(
          id: id,
          name: name,
          relation: c['relationship_type'] as String? ?? 'Contact',
          phone: partner['phone'] as String? ?? '',
          initial: initial,
          avatarColor: color,
          partnerUserId: partner['id'] as String?,
        ));

        if (streak > 0) {
          _streakDays[id] = streak;
          if (lastAt != null) {
            final dt = DateTime.tryParse(lastAt);
            if (dt != null) _lastSentDate[id] = dt;
          }
        }

        changed = true;
      }

      if (changed) {
        notifyListeners();
        _persistContacts(); // fire-and-forget; errors are caught internally
      }
    } catch (_) {
      // Network unavailable — in-memory state remains unchanged.
    } finally {
      // Always clear loading — no more silent empty-state flash.
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // ── Local contact cache (SharedPreferences) ───────────────────────────────

  Future<void> _persistContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _diaries.map((d) => {
        'id':         d.id,
        'name':       d.name,
        'relation':   d.relation,
        'phone':      d.phone,
        'initial':    d.initial,
        'colorIndex': d.avatarColorIndex,
        'customLabel': d.customLabel,
        'partnerUserId': d.partnerUserId,
      }).toList();
      await prefs.setString(_kContactsCache, jsonEncode(list));

      final streaks = <String, dynamic>{};
      for (final d in _diaries) {
        final days = _streakDays[d.id] ?? 0;
        if (days > 0) {
          streaks[d.id] = {
            'days':     days,
            'lastSent': _lastSentDate[d.id]?.toIso8601String(),
          };
        }
      }
      await prefs.setString(_kStreakCache, jsonEncode(streaks));
    } catch (_) {}
  }

  Future<void> _loadCachedContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kContactsCache);
      if (raw == null) return;

      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final id = m['id'] as String? ?? '';
        if (id.isEmpty || has(id)) continue;
        final name = m['name'] as String? ?? '';
        if (name.isEmpty) continue;

        final colorIndex = m['colorIndex'] as int? ?? -1;
        final colorHash  = name.codeUnits.fold(0, (a, b) => a + b);
        final color = DiaryContact.avatarPalette[
            colorHash % DiaryContact.avatarPalette.length];

        _diaries.add(DiaryContact(
          id:             id,
          name:           name,
          relation:       m['relation']   as String? ?? 'Contact',
          phone:          m['phone']      as String? ?? '',
          initial:        m['initial']    as String? ??
                            (name.isNotEmpty ? name[0].toUpperCase() : '?'),
          avatarColor:    color,
          avatarColorIndex: colorIndex,
          customLabel:    m['customLabel'] as String? ?? '',
          partnerUserId:  m['partnerUserId'] as String?,
        ));
      }

      final streakRaw = prefs.getString(_kStreakCache);
      if (streakRaw != null) {
        final streaks = jsonDecode(streakRaw) as Map<String, dynamic>;
        for (final entry in streaks.entries) {
          final data = entry.value as Map<String, dynamic>;
          final days = data['days'] as int? ?? 0;
          if (days > 0) {
            _streakDays[entry.key] = days;
            final lastSent = data['lastSent'] as String?;
            if (lastSent != null) {
              final dt = DateTime.tryParse(lastSent);
              if (dt != null) _lastSentDate[entry.key] = dt;
            }
          }
        }
      }
    } catch (_) {}
  }

  void _clearPersistedContacts() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_kContactsCache);
      prefs.remove(_kStreakCache);
    }).catchError((_) {});
  }

  /// Called when a queued upload finally succeeds. Replaces the pending
  /// DiaryEntry (identified by [pendingId]) with the real backend entry ID
  /// and marks it as delivered.
  void markUploadComplete(String pendingId, String realEntryId) {
    for (final diaryId in _entries.keys) {
      final list = _entries[diaryId]!;
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == pendingId) {
          final old = list[i];
          list[i] = old.copyWith(
            id: realEntryId,
            isPending: false,
            isFailed: false,
          );
          final snippet = old.type == 'voice' ? '🎙 Voice note' : '🎬 Video clip';
          final now = DateTime.now();
          final h = now.hour == 0 ? 12 : (now.hour > 12 ? now.hour - 12 : now.hour);
          final m = now.minute.toString().padLeft(2, '0');
          final period = now.hour >= 12 ? 'PM' : 'AM';
          updateSnippet(old.diaryId, snippet, '$h:$m $period');
          _schedulePersistEntries(old.diaryId);
          return;
        }
      }
    }
  }

  /// Called when an upload fails. Keeps the entry visible with isFailed: true
  /// so the user sees a retry indicator in the thread rather than a silent loss.
  void markUploadFailed(String pendingId) {
    for (final diaryId in _entries.keys) {
      final list = _entries[diaryId]!;
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == pendingId) {
          list[i] = list[i].copyWith(isPending: false, isFailed: true);
          // Update snippet to reflect failed state.
          final idx = _diaries.indexWhere((d) => d.id == diaryId);
          if (idx != -1 && _diaries[idx].lastSnippet == '⏳ Sending...') {
            _diaries[idx] = _diaries[idx].copyWith(
              lastSnippet: '⚠️ Failed — will retry',
              lastTime: '',
            );
          }
          notifyListeners();
          return;
        }
      }
    }
  }

  /// Called when a queued text message finally delivers. Replaces temp ID
  /// with the real backend entry ID.
  void markTextSent(String pendingId, String realEntryId) {
    for (final diaryId in _entries.keys) {
      final list = _entries[diaryId]!;
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == pendingId) {
          final old = list[i];
          list[i] = old.copyWith(
            id: realEntryId,
            path: '',
            isPending: false,
            isFailed: false,
          );
          final now = DateTime.now();
          final h = now.hour == 0 ? 12 : (now.hour > 12 ? now.hour - 12 : now.hour);
          final m = now.minute.toString().padLeft(2, '0');
          final period = now.hour >= 12 ? 'PM' : 'AM';
          updateSnippet(old.diaryId, '💬 ${old.content ?? 'Text'}', '$h:$m $period');
          notifyListeners();
          return;
        }
      }
    }
  }

  /// Called when an offline text message fails to send.
  void markTextFailed(String pendingId) {
    for (final diaryId in _entries.keys) {
      final list = _entries[diaryId]!;
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == pendingId) {
          list[i] = list[i].copyWith(
            path: '',
            isPending: false,
            isFailed: true,
          );
          notifyListeners();
          return;
        }
      }
    }
  }

  /// Marks a text entry as saved to Moments (Memory Tree).
  void markSavedToMoments(String entryId) {
    _updateSavedToMoments(entryId, saved: true);
  }

  /// Removes a text entry from Moments (Memory Tree).
  void markRemovedFromMoments(String entryId) {
    _updateSavedToMoments(entryId, saved: false);
  }

  void _updateSavedToMoments(String entryId, {required bool saved}) {
    for (final list in _entries.values) {
      for (int i = 0; i < list.length; i++) {
        if (list[i].id == entryId) {
          list[i] = list[i].copyWith(
            isPending: false,
            isFailed: false,
            savedToMoments: saved,
          );
          notifyListeners();
          return;
        }
      }
    }
  }

  void add(DiaryContact contact) {
    if (has(contact.id)) return;
    _diaries.insert(0, contact);
    notifyListeners();
  }

  void updateSnippet(String id, String snippet, String time, {String? prompt}) {
    final idx = _diaries.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    _diaries[idx] =
        _diaries[idx].copyWith(lastSnippet: snippet, lastTime: time);
    // Move to front (pinned ordering handled by getter).
    if (!_pinned.contains(id)) {
      final updated = _diaries.removeAt(idx);
      _diaries.insert(0, updated);
    }
    // Voice notes (🎙) and video clips (🎬) count toward the streak.
    if (snippet.contains('🎙') || snippet.contains('🎬')) {
      _recordSend(id);
    }
    notifyListeners();
  }

  void remove(String id) {
    _diaries.removeWhere((d) => d.id == id);
    _pinned.remove(id);
    _muted.remove(id);
    _favourites.remove(id);
    _locked.remove(id);
    _archived.remove(id);
    _streakDays.remove(id);
    _lastSentDate.remove(id);
    _streakJustBroke.remove(id);
    _brokeStreakPreviousDays.remove(id);
    _justResumed.remove(id);
    _milestoneReached.remove(id);
    _jarredEntries.remove(id);
    _occasionTag.remove(id);
    _entries.remove(id);
    notifyListeners();
  }

  // ── Per-diary actions ─────────────────────────────────────────────────────

  void togglePin(String id) {
    _pinned.contains(id) ? _pinned.remove(id) : _pinned.add(id);
    notifyListeners();
  }

  void toggleMute(String id) {
    _muted.contains(id) ? _muted.remove(id) : _muted.add(id);
    notifyListeners();
  }

  void toggleFavourite(String id) {
    _favourites.contains(id)
        ? _favourites.remove(id)
        : _favourites.add(id);
    notifyListeners();
  }

  // ── Messaging actions ──────────────────────────────────────────────────────

  /// Partner-is-recording indicator per diary, driven by SSE partner_recording.
  final Map<String, String> _recordingPartners = {}; // diaryId -> entryType
  String? recordingType(String diaryId) => _recordingPartners[diaryId];

  void setPartnerRecording(String diaryId, bool isRecording, String type) {
    if (isRecording) {
      _recordingPartners[diaryId] = type;
      // Safety: auto-clear after 30s in case the stop signal is lost.
      Future.delayed(const Duration(seconds: 30), () {
        if (_recordingPartners[diaryId] == type) {
          _recordingPartners.remove(diaryId);
          notifyListeners();
        }
      });
    } else {
      _recordingPartners.remove(diaryId);
    }
    notifyListeners();
  }

  DiaryEntry? _findEntry(String entryId) {
    for (final list in _entries.values) {
      for (final e in list) {
        if (e.id == entryId) return e;
      }
    }
    return null;
  }

  void updateEntryReactions(String entryId, Map<String, List<String>> reactions) {
    final e = _findEntry(entryId);
    if (e == null) return;
    e.emojiReactions = reactions;
    _schedulePersistEntries(e.diaryId);
    notifyListeners();
  }

  void updateEntryCaption(String entryId, String? caption) {
    final e = _findEntry(entryId);
    if (e == null) return;
    e.caption = caption;
    _schedulePersistEntries(e.diaryId);
    notifyListeners();
  }

  void setEntryPinned(String entryId, bool pinned) {
    final e = _findEntry(entryId);
    if (e == null) return;
    e.isPinned = pinned;
    _schedulePersistEntries(e.diaryId);
    notifyListeners();
  }

  void toggleLock(String id) {
    _locked.contains(id) ? _locked.remove(id) : _locked.add(id);
    notifyListeners();
  }

  void archive(String id) {
    _archived.add(id);
    notifyListeners();
  }

  void unarchive(String id) {
    _archived.remove(id);
    notifyListeners();
  }

  void clearChat(String id) {
    final idx = _diaries.indexWhere((d) => d.id == id);
    if (idx == -1) return;
    _diaries[idx] = _diaries[idx].copyWith(
      lastSnippet: '🎙 Tap to send your first voice note',
      lastTime: 'Now',
    );
    _entries.remove(id); // clear all entries too
    notifyListeners();
  }

  /// Blocks = permanent removal from the list.
  void block(String id) => remove(id);
}

