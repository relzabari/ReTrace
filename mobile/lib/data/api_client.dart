import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient(this.baseUrl);
  final String baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final response = await http.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await http.get(_uri(path));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listActiveExercises() async {
    final data = await _get('/exercises');
    return (data['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((exercise) => exercise['status'] == 'ACTIVE')
        .toList();
  }

  Future<Map<String, dynamic>> createExercise(String name) =>
      _post('/exercises', {'name': name, 'timezone': 'Asia/Jerusalem'});

  Future<Map<String, dynamic>> addParticipant({
    required String exerciseId,
    required String displayName,
    required String role,
  }) =>
      _post('/exercises/$exerciseId/participants', {
        'display_name': displayName,
        'callsign': null,
        'role': role,
        'tracking_mode': 'CONTINUOUS_GPS',
      });

  Future<Map<String, dynamic>> createDeviceSession({
    required String exerciseId,
    required String participantId,
    required String deviceId,
  }) =>
      _post('/exercises/$exerciseId/device-sessions', {
        'participant_id': participantId,
        'device_id': deviceId,
        'clock_offset_ms': 0,
      });

  Future<Map<String, dynamic>> startExercise(String exerciseId) =>
      _post('/exercises/$exerciseId/start', {});

  Future<Map<String, dynamic>> closeExercise(String exerciseId) =>
      _post('/exercises/$exerciseId/close', {});
}
