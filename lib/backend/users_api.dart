import 'package:dio/dio.dart';
import 'api_client.dart';

class UsersApi {
  UsersApi._();
  static final UsersApi instance = UsersApi._();

  Dio get _dio => ApiClient.instance.dio;

  Future<void> updateProfile({required String name}) async {
    await _dio.put('/onboarding/profile', data: {'name': name});
  }

  Future<void> completeOnboarding() async {
    await _dio.post('/onboarding/complete');
  }

  // ── Safety ─────────────────────────────────────────────────────────────────

  /// Blocked pairs cannot exchange new memories — enforced server-side.
  Future<void> blockUser(String userId) async {
    await _dio.post('/users/block', data: {'user_id': userId});
  }

  Future<void> unblockUser(String userId) async {
    await _dio.delete('/users/block/$userId');
  }

  Future<void> reportUser(String userId, String reason,
      {String? details}) async {
    await _dio.post('/users/report', data: {
      'user_id': userId,
      'reason':  reason,
      'details': ?details,
    });
  }
}
