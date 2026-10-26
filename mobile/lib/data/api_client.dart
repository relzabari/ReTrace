import 'dart:convert';

import 'auth_session.dart';

class ApiClient {
  ApiClient(this.session);
  final AuthSession session;

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await session.request('POST', path, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await session.request('GET', path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await session.request('PATCH', path, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _delete(String path) async {
    final response = await session.request('DELETE', path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> listExercises() async {
    final data = await _get('/exercises');
    return (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listActiveExercises() async {
    final exercises = await listExercises();
    return exercises
        .where((exercise) => exercise['status'] == 'ACTIVE')
        .toList();
  }

  Future<Map<String, dynamic>> createExercise(String name) =>
      _post('/exercises', {'name': name, 'timezone': 'Asia/Jerusalem'});

  Future<Map<String, dynamic>> addParticipant({
    required String exerciseId,
    required String displayName,
    required String role,
  }) => _post('/exercises/$exerciseId/participants', {
    'display_name': displayName,
    'callsign': null,
    'role': role,
    'tracking_mode': 'CONTINUOUS_GPS',
  });

  Future<Map<String, dynamic>> createDeviceSession({
    required String exerciseId,
    required String participantId,
    required String deviceId,
  }) => _post('/exercises/$exerciseId/device-sessions', {
    'participant_id': participantId,
    'device_id': deviceId,
    'clock_offset_ms': 0,
  });

  Future<Map<String, dynamic>> startExercise(String exerciseId) =>
      _post('/exercises/$exerciseId/start', {});

  Future<Map<String, dynamic>> closeExercise(String exerciseId) =>
      _post('/exercises/$exerciseId/close', {});

  Future<Map<String, dynamic>> renameExercise(String exerciseId, String name) =>
      _patch('/exercises/$exerciseId', {'name': name});

  Future<void> deleteExercise(String exerciseId) =>
      _delete('/exercises/$exerciseId');

  Future<List<Map<String, dynamic>>> listUsers() async {
    final data = await _get('/users');
    return (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createUser({
    required String email,
    required String password,
    required String role,
  }) => _post('/users', {'email': email, 'password': password, 'role': role});

  Future<Map<String, dynamic>> updateUserRole(String userId, String role) =>
      _patch('/users/$userId/role', {'role': role});

  Future<void> deleteUser(String userId) => _delete('/users/$userId');

  Future<List<Map<String, dynamic>>> listExerciseAccess(
    String exerciseId,
  ) async {
    final data = await _get('/exercises/$exerciseId/access');
    return (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> grantExerciseAccess({
    required String exerciseId,
    required String email,
    String? participantId,
  }) => _post('/exercises/$exerciseId/access', {
    'email': email,
    'participant_id': participantId,
  });

  Future<void> revokeExerciseAccess(String exerciseId, String userId) =>
      _delete('/exercises/$exerciseId/access/$userId');

  Future<List<Map<String, dynamic>>> listParticipants(String exerciseId) async {
    final data = await _get('/exercises/$exerciseId/participants');
    return (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
  }
}
