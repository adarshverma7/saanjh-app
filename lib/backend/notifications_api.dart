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
      if (cursor != null) 'cursor': cursor,
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
      if (appVersion != null) 'app_version': appVersion,
      if (platform != null) 'platform': platform,
    });
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
