import 'package:dio/dio.dart';
import 'api_client.dart';

class NotificationsApi {
  NotificationsApi._();
  static final NotificationsApi instance = NotificationsApi._();

  Dio get _dio => ApiClient.instance.dio;

  Future<Map<String, dynamic>> listNotifications({
    String filter = 'all',
    int limit = 20,
    String? cursor,
  }) async {
    final res = await _dio.get('/notifications', queryParameters: {
      'filter': filter,
      'limit':  limit,
      'cursor': ?cursor,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<void> markAsRead(List<String> ids) async {
    await _dio.post('/notifications/read', data: {'ids': ids});
  }

  Future<void> registerDeviceToken({
    required String deviceId,
    required String fcmToken,
    String? appVersion,
    String? platform,
  }) async {
    await _dio.post('/notifications/device-token', data: {
      'device_id':   deviceId,
      'fcm_token':   fcmToken,
      'app_version': ?appVersion,
      'platform': ?platform,
    });
  }

  /// Returns the download link from the newest `data_export` notification
  /// created after [after], or null if none has arrived yet. Used to poll for
  /// a just-requested data export (notifications come back newest-first).
  Future<String?> latestDataExportUrl({required DateTime after}) async {
    final res = await listNotifications(filter: 'all', limit: 10);
    final items = (res['items'] as List?) ?? const [];
    for (final it in items) {
      if (it is! Map) continue;
      if (it['type'] != 'data_export') continue;
      final created = DateTime.tryParse(it['created_at']?.toString() ?? '');
      if (created == null || !created.isAfter(after)) continue;
      final data = it['data'];
      final url = data is Map ? data['download_url']?.toString() : null;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  Future<Map<String, dynamic>> getPreferences() async {
    final res = await _dio.get('/notifications/preferences');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updatePreferences(
      Map<String, dynamic> prefs) async {
    final res = await _dio.put('/notifications/preferences', data: prefs);
    return res.data as Map<String, dynamic>;
  }
}
