import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';

class EntriesApi {
  EntriesApi._();
  static final EntriesApi instance = EntriesApi._();

  Dio get _dio => ApiClient.instance.dio;

  // ── Upload flow ─────────────────────────────────────────────────────────────

  /// Step 1: get a canonical storage path + entry ID + signed upload URL from the backend.
  Future<UploadUrlResult> getUploadUrl({
    required String connectionId,
    required String entryType,       // 'voice' | 'video'
    required String fileExtension,   // 'm4a'   | 'mp4'
    required int durationSeconds,
    required int fileSizeBytes,
  }) async {
    final res = await _dio.post(
      '/connections/$connectionId/entries/upload-url',
      data: {
        'entry_type':       entryType,
        'file_extension':   fileExtension,
        'duration_seconds': durationSeconds,
        'file_size_bytes':  fileSizeBytes,
      },
    );
    return UploadUrlResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// Step 2: upload bytes directly to Supabase Storage via the signed URL.
  Future<void> uploadToStorage({
    required String uploadUrl,
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    // Separate Dio without auth interceptor — Supabase signed URLs are self-contained.
    // Stream-based upload triggers chunked transfer encoding (no Content-Length),
    // which Supabase rejects. Sending Uint8List directly lets Dio set Content-Length.
    final storageDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      // 5 min: a 20s video at high quality on slow connections can be 30-50 MB.
      sendTimeout: const Duration(seconds: 300),
      // 60 s: Supabase processes and responds after the upload stream closes.
      receiveTimeout: const Duration(seconds: 60),
      followRedirects: true,
      maxRedirects: 3,
    ));
    await storageDio.put(
      uploadUrl,
      data: bytes,
      options: Options(
        contentType: contentType,
        headers: {
          // Allow overwrite on retry — Supabase rejects a second PUT to the
          // same key without this flag (returns 400 "already exists").
          'x-upsert': 'true',
        },
      ),
      onSendProgress: onProgress,
    );
  }

  /// Step 3: confirm the entry with the backend (verifies upload completed).
  Future<Map<String, dynamic>> createEntry({
    required String connectionId,
    required String entryType,
    required String mediaKey,
    int? durationSeconds,
    String? mood,
    DateTime? recordedAt,
  }) async {
    final res = await _dio.post(
      '/connections/$connectionId/entries',
      data: {
        'entry_type':  entryType,
        'media_key':   mediaKey,
        'duration_seconds': ?durationSeconds,
        'mood': ?mood,
        'recorded_at': ?recordedAt?.toIso8601String(),
      },
    );
    return res.data as Map<String, dynamic>;
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> listEntries(
    String connectionId, {
    String? cursor,
    String? filter,
    int limit = 20,
  }) async {
    final res = await _dio.get(
      '/connections/$connectionId/entries',
      queryParameters: {
        'cursor': ?cursor,
        'filter': ?filter,
        'limit': limit,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  /// Diary thread — enforces 24-hour expiry (expired entries return no URL).
  Future<Map<String, dynamic>> getEntry(
      String connectionId, String entryId) async {
    final res = await _dio.get('/connections/$connectionId/entries/$entryId');
    return res.data as Map<String, dynamic>;
  }

  /// Memory Tree — bypasses expiry so old moments are always playable.
  Future<Map<String, dynamic>> getMomentsEntry(
      String connectionId, String entryId) async {
    final res = await _dio.get('/connections/$connectionId/entries/$entryId/moments');
    return res.data as Map<String, dynamic>;
  }

  Future<void> starEntry(
      String connectionId, String entryId, bool starred) async {
    await _dio.patch(
      '/connections/$connectionId/entries/$entryId/star',
      data: {'is_starred': starred},
    );
  }

  Future<void> recordPlay(String connectionId, String entryId) async {
    await _dio.patch('/connections/$connectionId/entries/$entryId/played');
  }

  Future<void> deleteEntry(String connectionId, String entryId) async {
    await _dio.delete('/connections/$connectionId/entries/$entryId');
  }

  /// Sends a text message — no upload step, content goes directly to the API.
  Future<Map<String, dynamic>> sendTextMessage({
    required String connectionId,
    required String content,
    String? mood,
    DateTime? recordedAt,
  }) async {
    final res = await _dio.post(
      '/connections/$connectionId/entries',
      data: {
        'entry_type': 'text',
        'content': content,
        if (mood != null) 'mood': mood,
        if (recordedAt != null) 'recorded_at': recordedAt.toIso8601String(),
      },
    );
    return res.data as Map<String, dynamic>;
  }

  /// Saves a text message to the Memory Tree (Moments).
  Future<Map<String, dynamic>> saveToMoments(
      String connectionId, String entryId) async {
    final res = await _dio.patch(
        '/connections/$connectionId/entries/$entryId/save-to-moments');
    return res.data as Map<String, dynamic>;
  }

  /// Removes a text message from the Memory Tree (Moments).
  Future<Map<String, dynamic>> removeFromMoments(
      String connectionId, String entryId) async {
    final res = await _dio.delete(
        '/connections/$connectionId/entries/$entryId/save-to-moments');
    return res.data as Map<String, dynamic>;
  }
}

class UploadUrlResult {
  final String mediaKey;
  final String entryId;
  final String uploadUrl;

  const UploadUrlResult({
    required this.mediaKey,
    required this.entryId,
    required this.uploadUrl,
  });

  factory UploadUrlResult.fromJson(Map<String, dynamic> j) => UploadUrlResult(
        mediaKey:  j['media_key']  as String,
        entryId:   j['entry_id']   as String,
        uploadUrl: j['upload_url'] as String,
      );
}
