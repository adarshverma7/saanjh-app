import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String kApiBaseUrl = 'https://web-production-01022.up.railway.app/v1';

const _kAccessToken  = 'access_token';
const _kRefreshToken = 'refresh_token';
const _kUserId       = 'user_id';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
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
  }) async {
    await Future.wait([
      _storage.write(key: _kAccessToken,  value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
      _storage.write(key: _kUserId,       value: userId),
    ]);
  }

  Future<String?> get accessToken  => _storage.read(key: _kAccessToken);
  Future<String?> get refreshToken => _storage.read(key: _kRefreshToken);
  Future<String?> get userId       => _storage.read(key: _kUserId);

  Future<bool> get isLoggedIn async =>
      (await _storage.read(key: _kAccessToken)) != null;

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
        final refresh = await _storage.read(key: _kRefreshToken);
        if (refresh == null) {
          await ApiClient.instance.clearTokens();
          handler.next(err);
          return;
        }

        // Attempt token refresh
        final refreshDio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
        final res = await refreshDio.post('/auth/token/refresh',
            data: {'refresh_token': refresh});

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
      } catch (_) {
        await ApiClient.instance.clearTokens();
        handler.next(err);
      } finally {
        _refreshing = false;
      }
    } else {
      handler.next(err);
    }
  }
}
