import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';

class EntriesApi {
  EntriesApi._();
  static final EntriesApi instance = EntriesApi._();

  Dio get _dio => ApiClient.instance.dio;

  // ── Telegram-style upload flow ──────────────────────────────────────────────

  /// Step 1: pre-create a pending DB row and get a 15-min presigned PUT URL.
  /// The entry_id is stable — use it in confirmUpload after the PUT completes.
  Future<RequestUploadResult> requestUpload({
    required String connectionId,
    required String entryType, // 'voice' | 'video'
    String? clientMsgId, // stable idempotency key, reused across retries
  }) async {
    final res = await _dio.post(
      '/connections/$connectionId/entries/request-upload',
      data: {
        'entry_type':    entryType,
        'client_msg_id': ?clientMsgId,
      },
    );
    return RequestUploadResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// Step 2: upload bytes directly to Backblaze B2 via the presigned PUT URL.
  ///
  /// Uses a raw dart:io [HttpClient] rather than Dio on purpose: the presigned
  /// URL carries an already-encoded AWS SigV4 query string (X-Amz-Credential
  /// contains %2F, plus the signature), and Dio re-parses/re-encodes the query
  /// when composing the request, which corrupts the signature and makes B2
  /// reject every upload with 403. HttpClient sends the parsed [Uri] verbatim,
  /// so the signature stays intact. (This is why media uploads never worked
  /// while text — a plain JSON POST with no presigned URL — always did.)
  Future<void> uploadToStorage({
    required String uploadUrl,
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.putUrl(Uri.parse(uploadUrl));
      req.headers.contentType = ContentType.parse(contentType);
      req.headers.contentLength = bytes.length;

      // Write in chunks so the caller can drive an upload-progress indicator.
      const chunk = 64 * 1024;
      var sent = 0;
      while (sent < bytes.length) {
        final end = (sent + chunk) < bytes.length ? sent + chunk : bytes.length;
        req.add(bytes.sublist(sent, end));
        sent = end;
        onProgress?.call(sent, bytes.length);
      }

      final resp = await req.close();
      await resp.drain<void>();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw HttpException(
          'B2 upload failed with status ${resp.statusCode}',
          uri: Uri.parse(uploadUrl),
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Step 3: verify the B2 upload and mark the entry completed.
  /// Backend pushes an SSE new_entry event (with signed URL) to the partner.
  Future<Map<String, dynamic>> confirmUpload({
    required String connectionId,
    required String entryId,
    required int durationSeconds,
    DateTime? recordedAt,
    String? mood,
  }) async {
    final res = await _dio.post(
      '/connections/$connectionId/entries/confirm',
      data: {
        'entry_id':         entryId,
        'duration_seconds': durationSeconds,
        'recorded_at':      ?recordedAt?.toIso8601String(),
        'mood':             ?mood,
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
    final res =
        await _dio.get('/connections/$connectionId/entries/$entryId/moments');
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

  /// Sends a text message — no upload step needed, content goes directly to the API.
  Future<Map<String, dynamic>> sendTextMessage({
    required String connectionId,
    required String content,
    String? mood,
    DateTime? recordedAt,
    String? clientMsgId, // stable idempotency key, reused across retries
  }) async {
    final res = await _dio.post(
      '/connections/$connectionId/entries',
      data: {
        'entry_type':    'text',
        'content':       content,
        'mood':          ?mood,
        'recorded_at':   ?recordedAt?.toIso8601String(),
        'client_msg_id': ?clientMsgId,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  /// Saves a text message to the Memory Tree (Moments).
  Future<Map<String, dynamic>> saveToMoments(
      String connectionId, String entryId) async {
    final res = await _dio
        .patch('/connections/$connectionId/entries/$entryId/save-to-moments');
    return res.data as Map<String, dynamic>;
  }

  /// Removes a text message from the Memory Tree (Moments).
  Future<Map<String, dynamic>> removeFromMoments(
      String connectionId, String entryId) async {
    final res = await _dio
        .delete('/connections/$connectionId/entries/$entryId/save-to-moments');
    return res.data as Map<String, dynamic>;
  }
}

// ── Result types ──────────────────────────────────────────────────────────────

class RequestUploadResult {
  final String entryId;
  final String mediaKey;
  final String uploadUrl;
  final String expiresAt; // ISO timestamp

  const RequestUploadResult({
    required this.entryId,
    required this.mediaKey,
    required this.uploadUrl,
    required this.expiresAt,
  });

  factory RequestUploadResult.fromJson(Map<String, dynamic> j) =>
      RequestUploadResult(
        entryId:   j['entry_id']   as String,
        mediaKey:  j['media_key']  as String,
        uploadUrl: j['upload_url'] as String,
        expiresAt: j['expires_at'] as String,
      );
}
