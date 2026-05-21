import 'package:dio/dio.dart';
import 'api_client.dart';

class EntriesApi {
  EntriesApi._();
  static final EntriesApi instance = EntriesApi._();

  Dio get _dio => ApiClient.instance.dio;

  // ── Upload flow ─────────────────────────────────────────────────────────────

  /// Step 1: get a pre-signed R2 URL for direct upload.
  Future<UploadUrlResult> getUploadUrl({
    required String connectionId,
    required String entryType,  // 'voice' | 'video'
    required String mimeType,
    required int fileSize,
  }) async {
    final res = await _dio.post(
      '/connections/$connectionId/entries/upload-url',
      data: {
        'entry_type': entryType,
        'mime_type':  mimeType,
        'file_size':  fileSize,
      },
    );
    return UploadUrlResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// Step 2: upload bytes directly to R2 (NOT through the API server).
  Future<void> uploadToR2({
    required String presignedUrl,
    required List<int> bytes,
    required String mimeType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final uploadDio = Dio(); // plain Dio — no auth headers
    await uploadDio.put(
      presignedUrl,
      data: Stream.fromIterable(bytes.map((b) => [b])),
      options: Options(
        headers: {
          'Content-Type':   mimeType,
          'Content-Length': bytes.length,
        },
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
      ),
      onSendProgress: onProgress,
    );
  }

  /// Step 3: confirm the entry with the backend.
  Future<Map<String, dynamic>> createEntry({
    required String connectionId,
    required String entryType,
    required String mediaKey,
    required String mimeType,
    int? durationSeconds,
    String? mood,
    DateTime? recordedAt,
  }) async {
    final res = await _dio.post(
      '/connections/$connectionId/entries',
      data: {
        'entry_type':       entryType,
        'media_key':        mediaKey,
        'mime_type':        mimeType,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (mood != null) 'mood': mood,
        if (recordedAt != null) 'recorded_at': recordedAt.toIso8601String(),
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
        if (cursor != null) 'cursor': cursor,
        if (filter != null) 'filter': filter,
        'limit': limit,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getEntry(
      String connectionId, String entryId) async {
    final res = await _dio.get('/connections/$connectionId/entries/$entryId');
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
  final String uploadUrl;
  final String mediaKey;

  const UploadUrlResult({required this.uploadUrl, required this.mediaKey});

  factory UploadUrlResult.fromJson(Map<String, dynamic> j) => UploadUrlResult(
        uploadUrl: j['upload_url'] as String,
        mediaKey:  j['media_key']  as String,
      );
}
