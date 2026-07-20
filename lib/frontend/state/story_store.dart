import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/api_client.dart';
import '../../backend/entries_api.dart';
import '../../backend/stories_api.dart';

/// One story (photo / video / audio) inside a user's group.
class StoryItem {
  final String id;
  final String userId;
  final String mediaType; // 'photo' | 'video' | 'audio'
  final String mediaUrl; // 1-hour signed URL
  final String? caption;
  final int? durationSeconds;
  final DateTime createdAt;
  final DateTime expiresAt;
  bool viewed;
  final int viewCount;

  StoryItem({
    required this.id,
    required this.userId,
    required this.mediaType,
    required this.mediaUrl,
    required this.caption,
    required this.durationSeconds,
    required this.createdAt,
    required this.expiresAt,
    required this.viewed,
    required this.viewCount,
  });

  factory StoryItem.fromJson(Map<String, dynamic> j) => StoryItem(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        mediaType: j['media_type'] as String,
        mediaUrl: j['media_url'] as String? ?? '',
        caption: j['caption'] as String?,
        durationSeconds: j['duration_seconds'] as int?,
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        expiresAt: DateTime.tryParse(j['expires_at'] as String? ?? '') ??
            DateTime.now().add(const Duration(hours: 24)),
        viewed: j['viewed'] as bool? ?? false,
        viewCount: j['view_count'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'media_type': mediaType,
        'media_url': mediaUrl,
        'caption': caption,
        'duration_seconds': durationSeconds,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'viewed': viewed,
        'view_count': viewCount,
      };

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// All active stories from one user, Instagram-style.
class StoryGroup {
  final String userId;
  final String? name;
  final String? avatarUrl;
  final bool isSelf;
  final List<StoryItem> stories;

  StoryGroup({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.isSelf,
    required this.stories,
  });

  factory StoryGroup.fromJson(Map<String, dynamic> j) => StoryGroup(
        userId: j['user_id'] as String,
        name: j['name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        isSelf: j['is_self'] as bool? ?? false,
        stories: ((j['stories'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(StoryItem.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'name': name,
        'avatar_url': avatarUrl,
        'is_self': isSelf,
        'stories': stories.map((s) => s.toJson()).toList(),
      };

  bool get allViewed => stories.every((s) => s.viewed);
  List<StoryItem> get live =>
      stories.where((s) => !s.isExpired).toList(growable: false);
}

/// Singleton store behind the Flicker stories strip and the story viewer.
///
/// Cache strategy mirrors the entry cache: last server response persists in
/// SharedPreferences so the strip renders instantly at startup; a background
/// refresh then reconciles. Signed URLs in the cache go stale after ~1 hour —
/// the viewer falls back to a refresh when an image fails to load.
class StoryStore extends ChangeNotifier {
  StoryStore._();
  static final StoryStore instance = StoryStore._();

  static const _kCacheKey = 'story_groups_cache_v1';

  List<StoryGroup> _groups = [];
  bool _loaded = false;
  bool _loading = false;
  DateTime? _lastFetch;

  List<StoryGroup> get groups => _groups
      .where((g) => g.live.isNotEmpty)
      .toList(growable: false);
  bool get isLoaded => _loaded;

  StoryGroup? get selfGroup {
    for (final g in groups) {
      if (g.isSelf) return g;
    }
    return null;
  }

  List<StoryGroup> get partnerGroups =>
      groups.where((g) => !g.isSelf).toList(growable: false);

  StoryGroup? groupForUser(String userId) {
    for (final g in groups) {
      if (g.userId == userId) return g;
    }
    return null;
  }

  // ── Load / refresh ─────────────────────────────────────────────────────────

  /// Restores the cached strip instantly, then refreshes from the server.
  Future<void> load() async {
    if (!_loaded) await _restoreCache();
    await refresh();
  }

  Future<void> refresh({bool force = false}) async {
    if (_loading) return;
    // Debounce SSE-driven refreshes to at most one per 5 s.
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(seconds: 5)) {
      return;
    }
    _loading = true;
    try {
      final raw = await StoriesApi.instance.listGroups();
      _groups = raw.map(StoryGroup.fromJson).toList();
      _loaded = true;
      _lastFetch = DateTime.now();
      notifyListeners();
      _persistCache();
    } catch (_) {
      // Offline / server hiccup — keep showing whatever we have.
    } finally {
      _loading = false;
    }
  }

  // ── View tracking ──────────────────────────────────────────────────────────

  /// Marks a story viewed: ring turns green locally at once; server call is
  /// best-effort (idempotent, so retried naturally on the next open).
  void markViewed(StoryItem story) {
    if (story.viewed) return;
    story.viewed = true;
    notifyListeners();
    _persistCache();
    StoriesApi.instance.markViewed(story.id).catchError((_) {});
  }

  // ── Publish ────────────────────────────────────────────────────────────────

  /// Full publish pipeline: request-upload → direct B2 PUT → confirm.
  /// Returns when the story is live; throws on failure so the capture screen
  /// can show a retry.
  Future<void> publish({
    required String mediaType, // 'photo' | 'video' | 'audio'
    required Uint8List bytes,
    String? caption,
    int? durationSeconds,
    void Function(double progress)? onProgress,
  }) async {
    final req = await StoriesApi.instance.requestUpload(mediaType: mediaType);
    final contentType = switch (mediaType) {
      'photo' => 'image/jpeg',
      'video' => 'video/mp4',
      _ => 'audio/mp4',
    };
    await EntriesApi.instance.uploadToStorage(
      uploadUrl: req.uploadUrl,
      bytes: bytes,
      contentType: contentType,
      onProgress: (sent, total) =>
          onProgress?.call(total == 0 ? 0 : sent / total),
    );
    await StoriesApi.instance.confirmUpload(
      storyId: req.entryId,
      caption: (caption?.trim().isNotEmpty ?? false) ? caption!.trim() : null,
      durationSeconds: durationSeconds,
    );
    await refresh(force: true);
  }

  /// Author-only viewer list for one story.
  Future<List<Map<String, dynamic>>> viewersOf(String storyId) =>
      StoriesApi.instance.listViewers(storyId);

  /// Author delete — story disappears everywhere.
  Future<void> deleteStory(StoryItem story) async {
    await StoriesApi.instance.deleteStory(story.id);
    for (final g in _groups) {
      g.stories.removeWhere((s) => s.id == story.id);
    }
    _groups.removeWhere((g) => g.stories.isEmpty);
    notifyListeners();
    _persistCache();
  }

  // ── Sign-out hygiene ───────────────────────────────────────────────────────

  Future<void> clear() async {
    _groups = [];
    _loaded = false;
    _lastFetch = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCacheKey);
  }

  // ── Cache ──────────────────────────────────────────────────────────────────

  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCacheKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final restored = list.map(StoryGroup.fromJson).toList();
      // Cache may belong to a previous account on this device.
      final uid = await ApiClient.instance.userId;
      final selfOk = restored
          .where((g) => g.isSelf)
          .every((g) => uid == null || g.userId == uid);
      if (!selfOk) return;
      _groups = restored;
      if (groups.isNotEmpty) {
        _loaded = true;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCacheKey,
        jsonEncode(_groups.map((g) => g.toJson()).toList()),
      );
    } catch (_) {}
  }
}
