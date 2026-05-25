import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

class AuthApi {
  AuthApi._();
  static final AuthApi instance = AuthApi._();

  Dio get _dio => ApiClient.instance.dio;

  // ── Firebase Phone Auth ────────────────────────────────────────────────────

  /// Step 1: triggers Firebase to send OTP SMS.
  /// [onCodeSent] is called with the verificationId when SMS is sent.
  /// [onError] is called with an error message if it fails.
  Future<void> sendOtp({
    required String phone,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    void Function(PhoneAuthCredential)? onAutoVerified,
  }) async {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) {
        // Auto-verified on Android (SMS auto-read)
        onAutoVerified?.call(credential);
      },
      verificationFailed: (e) {
        onError(e.message ?? 'Verification failed. Check your phone number.');
      },
      codeSent: (verificationId, _) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// Step 2: verifies the OTP entered by the user.
  /// Returns null if the OTP is wrong or any Firebase error occurs.
  Future<AuthResult?> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return await _signInWithCredential(credential);
    } on FirebaseAuthException {
      return null;
    }
  }

  /// For auto-verified credentials (Android SMS auto-read).
  Future<AuthResult?> verifyWithCredential(PhoneAuthCredential credential) =>
      _signInWithCredential(credential);

  // ── Backend exchange ───────────────────────────────────────────────────────

  Future<AuthResult?> _signInWithCredential(
      PhoneAuthCredential credential) async {
    try {
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await userCred.user?.getIdToken();
      if (idToken == null) return null;

      final deviceInfo = await _buildDeviceInfo();
      final res = await _dio.post('/auth/firebase/verify', data: {
        'id_token':    idToken,
        'device_id':   deviceInfo.deviceId,
        'device_type': deviceInfo.deviceType,
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
      await FirebaseAuth.instance.signOut();
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
      return _DeviceInfo(
          deviceId: 'unknown', deviceType: 'android', osVersion: '0');
    }
  }
}

class _DeviceInfo {
  final String deviceId;
  final String deviceType;
  final String osVersion;
  const _DeviceInfo(
      {required this.deviceId,
      required this.deviceType,
      required this.osVersion});
}

class AuthResult {
  final String accessToken;
  final String refreshToken;
  final String userId;
  final bool isNewUser;
  final bool isOnboarded;
  final String? name;

  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.isNewUser,
    required this.isOnboarded,
    this.name,
  });

  factory AuthResult.fromJson(Map<String, dynamic> j) {
    final user = j['user'] as Map<String, dynamic>;
    return AuthResult(
      accessToken:  j['access_token']  as String,
      refreshToken: j['refresh_token'] as String,
      userId:      user['id']          as String,
      isNewUser:   j['is_new_user']    as bool? ?? false,
      isOnboarded: user['is_onboarded'] as bool? ?? false,
      name:        user['name']         as String?,
    );
  }
}
