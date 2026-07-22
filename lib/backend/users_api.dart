import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'api_client.dart';
import 'entries_api.dart';

class UsersApi {
  UsersApi._();
  static final UsersApi instance = UsersApi._();

  Dio get _dio => ApiClient.instance.dio;

  // ── Profile ─────────────────────────────────────────────────────────────────

  /// Fetches the current user's profile (name, masked phone, language,
  /// timezone, signed avatar_url). Backed by GET /users/me.
  Future<UserProfile> getMyProfile() async {
    final res = await _dio.get('/users/me');
    return UserProfile.fromJson(res.data as Map<String, dynamic>);
  }

  /// Persists profile fields to the backend. Only [name] is required today;
  /// language is optional. Returns the refreshed profile.
  Future<UserProfile> updateProfile({
    required String name,
    String? language,
  }) async {
    final res = await _dio.put('/onboarding/profile', data: {
      'name': name,
      'language': ?language,
    });
    return UserProfile.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> completeOnboarding() async {
    await _dio.post('/onboarding/complete');
  }

  // ── Avatar ──────────────────────────────────────────────────────────────────

  /// Full avatar upload flow: presign → PUT bytes to B2 → confirm.
  /// Returns the refreshed profile (with a fresh signed avatar_url).
  ///
  /// The B2 PUT reuses [EntriesApi.uploadToStorage], which uses a raw
  /// dart:io HttpClient so the presigned SigV4 signature isn't corrupted by
  /// Dio re-encoding the query string.
  Future<UserProfile> uploadAvatar({
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    void Function(int sent, int total)? onProgress,
  }) async {
    final target = await _getAvatarUploadUrl();
    await EntriesApi.instance.uploadToStorage(
      uploadUrl: target.uploadUrl,
      bytes: bytes,
      contentType: contentType,
      onProgress: onProgress,
    );
    return _confirmAvatar(target.avatarKey);
  }

  /// Step 1: presigned B2 upload URL for the avatar.
  Future<_AvatarUploadTarget> _getAvatarUploadUrl() async {
    final res = await _dio.post('/onboarding/avatar/upload-url');
    final data = res.data as Map<String, dynamic>;
    return _AvatarUploadTarget(
      uploadUrl: data['upload_url'] as String,
      avatarKey: data['avatar_key'] as String,
    );
  }

  /// Step 3: confirm the upload completed and set users.avatar_key.
  Future<UserProfile> _confirmAvatar(String avatarKey) async {
    final res = await _dio.patch('/onboarding/avatar', data: {
      'avatar_key': avatarKey,
    });
    return UserProfile.fromJson(res.data as Map<String, dynamic>);
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

// ── Models ──────────────────────────────────────────────────────────────────

class UserProfile {
  final String id;
  final String phone; // masked — last 4 digits visible
  final String? name;
  final String language;
  final String timezone;
  final String? avatarUrl; // signed download URL (expires ~1h)
  final bool isOnboarded;
  final bool isVerified;

  const UserProfile({
    required this.id,
    required this.phone,
    required this.name,
    required this.language,
    required this.timezone,
    required this.avatarUrl,
    required this.isOnboarded,
    required this.isVerified,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id:          j['id'] as String,
        phone:       (j['phone'] as String?) ?? '',
        name:        j['name'] as String?,
        language:    (j['language'] as String?) ?? 'en',
        timezone:    (j['timezone'] as String?) ?? 'Asia/Kolkata',
        avatarUrl:   j['avatar_url'] as String?,
        isOnboarded: (j['is_onboarded'] as bool?) ?? false,
        isVerified:  (j['is_verified'] as bool?) ?? false,
      );
}

class _AvatarUploadTarget {
  final String uploadUrl;
  final String avatarKey;
  const _AvatarUploadTarget({required this.uploadUrl, required this.avatarKey});
}
