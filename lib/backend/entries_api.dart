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
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 30),
    ));
    await storageDio.put(
      uploadUrl,
      data: bytes,
      options: Options(
        headers: {'Content-Type': contentType},
        // Prevent Dio from overriding the content-type we set.
        contentType: contentType,
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
