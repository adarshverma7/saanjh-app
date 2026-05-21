import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class AuthApi {
  AuthApi._();
  static final AuthApi instance = AuthApi._();

  Dio get _dio => ApiClient.instance.dio;

  // ── OTP ────────────────────────────────────────────────────────────────────

  /// Sends a 6-digit OTP to the given phone number.
  /// [phone] must be in E.164 format e.g. "+919876543210"
  Future<void> sendOtp(String phone) async {
    await _dio.post('/auth/otp/send', data: {'phone': phone});
  }

  /// Verifies OTP and returns tokens + user info.
  /// Returns null on failure (handled by caller).
  Future<AuthResult?> verifyOtp(String phone, String otp) async {
    final deviceInfo = await _buildDeviceInfo();
    try {
      final res = await _dio.post('/auth/otp/verify', data: {
        'phone': phone,
        'otp': otp,
        'device_id':   deviceInfo.deviceId,
        'device_type': deviceInfo.deviceType,
        'os_version':  deviceInfo.osVersion,
        'app_version': '1.0.0',
      });
      return AuthResult.fromJson(res.data as Map<String, dynamic>);
    } on DioException {
      return null;
    }
  }

  Future<void> logout(String deviceId) async {
    try {
      await _dio.post('/auth/logout', data: {'device_id': deviceId});
    } catch (_) {}
    await ApiClient.instance.clearTokens();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<_DeviceInfo> _buildDeviceInfo() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await plugin.androidInfo;
        return _DeviceInfo(
          deviceId:   info.id,
          deviceType: 'android',
          osVersion:  info.version.release,
        );
      } else {
        final info = await plugin.iosInfo;
        return _DeviceInfo(
          deviceId:   info.identifierForVendor ?? 'unknown',
          deviceType: 'ios',
          osVersion:  info.systemVersion,
        );
      }
    } catch (_) {
      return _DeviceInfo(deviceId: 'unknown', deviceType: 'android', osVersion: '0');
    }
  }
}

class _DeviceInfo {
  final String deviceId;
  final String deviceType;
  final String osVersion;
  const _DeviceInfo({
    required this.deviceId,
    required this.deviceType,
    required this.osVersion,
  });
}

class AuthResult {
  final String accessToken;
  final String refreshToken;
  final String userId;
  final bool isNewUser;
  final bool isOnboarded;

  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.isNewUser,
    required this.isOnboarded,
  });

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        accessToken:  j['access_token']  as String,
        refreshToken: j['refresh_token'] as String,
        userId:       (j['user'] as Map<String, dynamic>)['id'] as String,
        isNewUser:    j['is_new_user']   as bool? ?? false,
        isOnboarded:  (j['user'] as Map<String, dynamic>)['is_onboarded'] as bool? ?? false,
      );
}
