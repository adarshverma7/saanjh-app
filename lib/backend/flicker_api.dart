import 'package:dio/dio.dart';
import 'api_client.dart';

class FlickerApi {
  FlickerApi._();
  static final FlickerApi instance = FlickerApi._();

  Dio get _dio => ApiClient.instance.dio;

  Future<Map<String, dynamic>> sendFlicker(String connectionId) async {
    final res = await _dio.post('/connections/$connectionId/flicker');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getFlickerStatus(String connectionId) async {
    final res = await _dio.get('/connections/$connectionId/flicker/latest');
    return res.data as Map<String, dynamic>;
  }

  /// SSE event stream for real-time updates. Auto-reconnects on error.
  ///
  /// Emits a synthetic `{"type":"stream_reconnected"}` event on every reconnect
  /// (not on initial connect) so FlickerStore can re-fetch authoritative state
  /// for any events missed during the disconnect window.
  Stream<String> subscribeToEvents(String connectionId) async* {
    final token = await ApiClient.instance.accessToken;
    final url = '$kApiBaseUrl/connections/$connectionId/events';

    bool hasConnected = false;
    while (true) {
      try {
        final res = await _dio.get<ResponseBody>(
          url,
          options: Options(
            headers: {
              'Accept':        'text/event-stream',
              'Cache-Control': 'no-cache',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            responseType: ResponseType.stream,
          ),
        );

        // Emit reconnect sentinel after a successful re-connection.
        // Skipped on first connect — loadFlickerStatus already runs at startup.
        if (hasConnected) {
          yield '{"type":"stream_reconnected"}';
        }
        hasConnected = true;

        await for (final chunk in res.data!.stream) {
          final text = String.fromCharCodes(chunk);
          for (final line in text.split('\n')) {
            if (line.startsWith('data:')) {
              yield line.substring(5).trim();
            }
          }
        }
      } catch (_) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }
}
