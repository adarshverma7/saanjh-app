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
}
