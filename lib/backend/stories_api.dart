import 'package:dio/dio.dart';

import 'api_client.dart';
import 'entries_api.dart';

/// Flicker Stories — Instagram-style 24-hour stories.
/// Media uses the same two-step flow as diary entries:
/// request-upload → direct B2 PUT (via [EntriesApi.uploadToStorage]) → confirm.
class StoriesApi {
  StoriesApi._();
  static final StoriesApi instance = StoriesApi._();

  Dio get _dio => ApiClient.instance.dio;

  /// Step 1: pre-create a pending story and get a 15-min presigned PUT URL.
  Future<RequestUploadResult> requestUpload({
    required String mediaType, // 'photo' | 'video' | 'audio'
  }) async {
    final res = await _dio.post(
      '/stories/request-upload',
      data: {'media_type': mediaType},
    );
    final j = res.data as Map<String, dynamic>;
    return RequestUploadResult(
      entryId:   j['story_id']   as String,
      mediaKey:  j['media_key']  as String,
      uploadUrl: j['upload_url'] as String,
      expiresAt: j['expires_at'] as String,
    );
  }

  /// Step 2 (after the B2 PUT): publish the story for 24 hours.
  Future<Map<String, dynamic>> confirmUpload({
    required String storyId,
    String? caption,
    int? durationSeconds,
  }) async {
    final res = await _dio.post(
      '/stories/confirm',
      data: {
        'story_id':         storyId,
        'caption':          ?caption,
        'duration_seconds': ?durationSeconds,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  /// All active stories grouped by user — own group first, then partners
  /// with unviewed stories, then fully-viewed groups.
  Future<List<Map<String, dynamic>>> listGroups() async {
    final res = await _dio.get('/stories');
    final groups = (res.data as Map<String, dynamic>)['groups'] as List? ?? [];
    return groups.cast<Map<String, dynamic>>();
  }

  /// Marks a story flickered (viewed) — turns its ring green for this user.
  Future<void> markViewed(String storyId) async {
    await _dio.post('/stories/$storyId/view');
  }

  /// Author-only: who has viewed this story, newest first.
  Future<List<Map<String, dynamic>>> listViewers(String storyId) async {
    final res = await _dio.get('/stories/$storyId/viewers');
    final viewers =
        (res.data as Map<String, dynamic>)['viewers'] as List? ?? [];
    return viewers.cast<Map<String, dynamic>>();
  }

  /// Author-only: removes the story everywhere.
  Future<void> deleteStory(String storyId) async {
    await _dio.delete('/stories/$storyId');
  }
}
