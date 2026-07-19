import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/entries_api.dart';

/// Offline-first media cache.
///
/// Every voice/video memory is stored on disk exactly once — keyed by entry id
/// — and played from the local file forever after. The network is touched only
/// when an entry has never been cached (or its file is corrupt).
///
/// Eviction is LRU by last-access time, bounded by [capBytes] (user-tunable via
/// the `media_cache_cap_mb` preference; clearing is exposed in Settings).
/// Pinned⁠/starred entries are preferred-kept by virtue of being re-accessed.
class MediaCacheService {
  MediaCacheService._();
  static final MediaCacheService instance = MediaCacheService._();

  static const _kIndexKey = 'media_cache_index_v1'; // {id: [lastAccessMs, size]}
  static const _kCapMbKey = 'media_cache_cap_mb';
  static const _kAutoDownloadKey = 'media_autodownload';
  static const _defaultCapMb = 500;

  Directory? _dir;

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/media_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  String _ext(String type) => type == 'video' ? 'mp4' : 'm4a';

  Future<File> _fileFor(String entryId, String type) async {
    final d = await _cacheDir();
    return File('${d.path}/$entryId.${_ext(type)}');
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns a local playable path for [entryId], downloading at most once.
  ///
  /// Resolution order:
  ///  1. Local cache hit (instant, offline-capable).
  ///  2. [signedUrl] if the caller already has one (e.g. from an SSE event).
  ///  3. A fresh signed URL fetched from the backend.
  /// Returns null only when the entry is uncached AND the network fails.
  Future<String?> resolve({
    required String diaryId,
    required String entryId,
    required String type, // 'voice' | 'video'
    String? signedUrl,
  }) async {
    final f = await _fileFor(entryId, type);
    if (await f.exists()) {
      if (await f.length() > 0) {
        _touch(entryId);
        return f.path;
      }
      await f.delete().catchError((_) => f); // corrupt zero-byte file
    }

    var url = signedUrl;
    if (url == null) {
      try {
        final data = await EntriesApi.instance.getEntry(diaryId, entryId);
        url = data['media_url'] as String?;
      } catch (_) {
        return null;
      }
    }
    if (url == null) return null;
    return _download(entryId, type, url);
  }

  /// Background prefetch from an already-signed URL (SSE new_entry). No-op if
  /// cached or auto-download is disabled.
  Future<void> prefetch(String entryId, String type, String url) async {
    if (!await autoDownloadEnabled) return;
    final f = await _fileFor(entryId, type);
    if (await f.exists() && await f.length() > 0) return;
    await _download(entryId, type, url);
  }

  /// Adopts a just-recorded local file so sent memories replay from cache
  /// without ever re-downloading what this device created.
  Future<void> adoptLocalRecording(
      String entryId, String type, String sourcePath) async {
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return;
      final dst = await _fileFor(entryId, type);
      await src.copy(dst.path);
      await _recordWrite(entryId, await dst.length());
    } catch (_) {/* cache adoption is best-effort */}
  }

  /// True when [entryId] can be played with zero network.
  Future<bool> isCached(String entryId, String type) async {
    final f = await _fileFor(entryId, type);
    return await f.exists() && await f.length() > 0;
  }

  Future<int> totalSizeBytes() async {
    final d = await _cacheDir();
    var total = 0;
    await for (final e in d.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// Wipes all downloaded media (Settings action + sign-out).
  Future<void> clear() async {
    final d = await _cacheDir();
    if (await d.exists()) await d.delete(recursive: true);
    _dir = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kIndexKey);
  }

  Future<bool> get autoDownloadEnabled async =>
      (await SharedPreferences.getInstance()).getBool(_kAutoDownloadKey) ?? true;

  Future<void> setAutoDownload(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kAutoDownloadKey, v);

  Future<int> get capMb async =>
      (await SharedPreferences.getInstance()).getInt(_kCapMbKey) ?? _defaultCapMb;

  Future<void> setCapMb(int mb) async =>
      (await SharedPreferences.getInstance()).setInt(_kCapMbKey, mb);

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<String?> _download(String entryId, String type, String url) async {
    try {
      final f = await _fileFor(entryId, type);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
      try {
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close();
        if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
        await resp.pipe(f.openWrite());
      } finally {
        client.close(force: true);
      }
      final size = await f.length();
      if (size == 0) {
        await f.delete().catchError((_) => f);
        return null;
      }
      await _recordWrite(entryId, size);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, List<num>>> _index() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kIndexKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as List).cast<num>()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveIndex(Map<String, List<num>> idx) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kIndexKey, jsonEncode(idx));
  }

  void _touch(String entryId) async {
    final idx = await _index();
    final cur = idx[entryId];
    idx[entryId] = [DateTime.now().millisecondsSinceEpoch, cur?[1] ?? 0];
    await _saveIndex(idx);
  }

  Future<void> _recordWrite(String entryId, int size) async {
    final idx = await _index();
    idx[entryId] = [DateTime.now().millisecondsSinceEpoch, size];
    await _saveIndex(idx);
    await _evictIfNeeded(idx);
  }

  /// LRU eviction: drop least-recently-accessed files until under the cap.
  Future<void> _evictIfNeeded(Map<String, List<num>> idx) async {
    final cap = (await capMb) * 1024 * 1024;
    var total = idx.values.fold<num>(0, (s, v) => s + (v.length > 1 ? v[1] : 0));
    if (total <= cap) return;

    final byOldest = idx.entries.toList()
      ..sort((a, b) => a.value[0].compareTo(b.value[0]));
    final d = await _cacheDir();
    for (final e in byOldest) {
      if (total <= cap) break;
      for (final ext in const ['m4a', 'mp4']) {
        final f = File('${d.path}/${e.key}.$ext');
        if (await f.exists()) await f.delete().catchError((_) => f);
      }
      total -= e.value.length > 1 ? e.value[1] : 0;
      idx.remove(e.key);
    }
    await _saveIndex(idx);
  }
}
