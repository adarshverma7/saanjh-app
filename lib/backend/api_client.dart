import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String kApiBaseUrl = String.fromEnvironment(
  'SAANJH_API_URL',
  defaultValue: 'https://saanjh-backend-x4od.onrender.com/v1',
);

const _kAccessToken  = 'access_token';
const _kRefreshToken = 'refresh_token';
const _kUserId       = 'user_id';
const _kDeviceId     = 'device_id';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  late final Dio dio = _buildDio();

  Dio _buildDio() {
    final d = Dio(BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    d.interceptors.add(_AuthInterceptor(_storage, d));
    return d;
  }

  // ── Token helpers ──────────────────────────────────────────────────────────

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
    String? deviceId,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccessToken,  value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
      _storage.write(key: _kUserId,       value: userId),
      if (deviceId != null) _storage.write(key: _kDeviceId, value: deviceId),
    ]);
  }

  /// The device_id used at login. The backend's /auth/token/refresh matches
  /// the session on (refresh_token_hash, device_id), so refresh MUST send
  /// the same device_id or it always 401s and the user gets logged out.
  Future<String?> get deviceId => _storage.read(key: _kDeviceId);

  Future<void> saveDeviceId(String deviceId) =>
      _storage.write(key: _kDeviceId, value: deviceId);

  Future<String?> get accessToken  => _storage.read(key: _kAccessToken);
  Future<String?> get refreshToken => _storage.read(key: _kRefreshToken);
  Future<String?> get userId       => _storage.read(key: _kUserId);

  Future<bool> get isLoggedIn async {
    try {
      return (await _storage.read(key: _kAccessToken)) != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kUserId),
    ]);
  }
}

// ── Auth Interceptor ────────────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;
  final Dio _dio;
  bool _refreshing = false;

  _AuthInterceptor(this._storage, this._dio);

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: _kAccessToken);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_refreshing) {
      _refreshing = true;
      try {
        final refresh  = await _storage.read(key: _kRefreshToken);
        final deviceId = await _storage.read(key: _kDeviceId);
        if (refresh == null) {
          await ApiClient.instance.clearTokens();
          handler.next(err);
          return;
        }

        // Attempt token refresh. device_id is REQUIRED by the backend — the
        // session row is matched on (refresh_token_hash, device_id).
        final refreshDio = Dio(BaseOptions(
          baseUrl: kApiBaseUrl,
          // Render free tier cold-starts can take 60-90s; a short timeout here
          // would fail the refresh and log the user out for no reason.
          connectTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 30),
        ));
        final res = await refreshDio.post('/auth/token/refresh', data: {
          'refresh_token': refresh,
          'device_id':     ?deviceId,
        });

        final newAccess  = res.data['access_token'] as String;
        final newRefresh = res.data['refresh_token'] as String;
        await Future.wait([
          _storage.write(key: _kAccessToken,  value: newAccess),
          _storage.write(key: _kRefreshToken, value: newRefresh),
        ]);

        // Retry original request
        final opts = err.requestOptions
          ..headers['Authorization'] = 'Bearer $newAccess';
        final retryRes = await _dio.fetch(opts);
        handler.resolve(retryRes);
      } on DioException catch (refreshErr) {
        // Only wipe the session when the server explicitly rejected the
        // refresh token. Transient failures (timeouts, cold starts, offline)
        // must NOT log the user out — that turns a hiccup into a dead app.
        final status = refreshErr.response?.statusCode;
        if (status != null && status >= 400 && status < 500) {
          await ApiClient.instance.clearTokens();
        }
        handler.next(err);
      } catch (_) {
        handler.next(err);
      } finally {
        _refreshing = false;
      }
    } else {
      handler.next(err);
    }
  }
}
