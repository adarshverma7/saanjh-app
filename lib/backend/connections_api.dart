import 'package:dio/dio.dart';
import 'api_client.dart';

class ConnectionsApi {
  ConnectionsApi._();
  static final ConnectionsApi instance = ConnectionsApi._();

  Dio get _dio => ApiClient.instance.dio;

  Future<Map<String, dynamic>> createInvite({
    required String relationshipType,
    required String connectionName,
    String? invitedPhone,
  }) async {
    final res = await _dio.post('/connections/invite', data: {
      'relationship_type': relationshipType,
      'connection_name': connectionName,
      'phone': ?invitedPhone,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getInviteDetails(String code) async {
    final res = await _dio.get('/connections/invite/$code');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> acceptInvite(String code, String name) async {
    final res = await _dio.post('/connections/invite/$code/accept', data: {
      'connection_name': name,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getConnections() async {
    final res = await _dio.get('/connections');
    final data = res.data;
    // Backend returns { "connections": [...] }; handle both shapes defensively.
    if (data is List) return data.cast<Map<String, dynamic>>();
    if (data is Map && data['connections'] is List) {
      return (data['connections'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Connects directly with an existing Saanjh user (both sides already on the app).
  /// Returns existing connection if one already exists, otherwise creates it.
  Future<Map<String, dynamic>> connectDirect({
    required String phone,
    required String connectionName,
    String relationshipType = 'friends',
  }) async {
    final res = await _dio.post('/connections/connect-direct', data: {
      'phone': phone,
      'connection_name': connectionName,
      'relationship_type': relationshipType,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getConnectionHealth(String connectionId) async {
    final res = await _dio.get('/connections/$connectionId/health');
    return res.data as Map<String, dynamic>;
  }

  Future<void> renameConnection(
      String connectionId, String nameForMe, String nameForThem) async {
    await _dio.patch('/connections/$connectionId/name', data: {
      'name_for_me':   nameForMe,
      'name_for_them': nameForThem,
    });
  }
}
