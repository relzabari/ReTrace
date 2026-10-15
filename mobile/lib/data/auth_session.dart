import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
  });

  final String id;
  final String email;
  final String role;

  bool get canManageExercises => role == 'ADMIN' || role == 'MANAGER';
  bool get isAdmin => role == 'ADMIN';

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'].toString(),
        email: json['email'].toString(),
        role: json['role'].toString(),
      );
}

class AuthSession {
  AuthSession._({
    required this.serverUrl,
    required String accessToken,
    required String refreshToken,
    required this.user,
  })  : _accessToken = accessToken,
        _refreshToken = refreshToken;

  static const defaultServerUrl =
      'https://retrace-exercise-platform.onrender.com';
  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _storage = FlutterSecureStorage();

  final String serverUrl;
  String _accessToken;
  String _refreshToken;
  AuthUser user;
  Future<void>? _refreshInProgress;
  bool _loggingOut = false;
  bool _ended = false;

  static Future<AuthSession> login({
    required String email,
    required String password,
    String serverUrl = defaultServerUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$serverUrl/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
    if (response.statusCode != 200) {
      throw StateError('כתובת המייל או הסיסמה שגויות.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final session = AuthSession._fromResponse(serverUrl, data);
    await session._persist();
    return session;
  }

  static Future<void> requestPasswordReset({
    required String email,
    String serverUrl = defaultServerUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$serverUrl/api/v1/auth/password-reset/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim()}),
    );
    if (response.statusCode == 429) {
      throw StateError('נשלחו יותר מדי בקשות. יש להמתין מעט ולנסות שוב.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('לא ניתן לשלוח כרגע קישור לאיפוס סיסמה.');
    }
  }

  static Future<AuthSession?> restore({
    String serverUrl = defaultServerUrl,
  }) async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (accessToken == null || refreshToken == null) return null;
    final temporary = AuthSession._(
      serverUrl: serverUrl,
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: const AuthUser(id: '', email: '', role: 'USER'),
    );
    try {
      var response = await temporary._send('GET', '/auth/me');
      if (response.statusCode == 401) {
        await temporary._refresh();
        response = await temporary._send('GET', '/auth/me');
      }
      if (response.statusCode != 200) throw StateError('Session expired');
      temporary.user = AuthUser.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      return temporary;
    } catch (_) {
      await temporary._clearLocalSession();
      return null;
    }
  }

  factory AuthSession._fromResponse(
    String serverUrl,
    Map<String, dynamic> data,
  ) =>
      AuthSession._(
        serverUrl: serverUrl,
        accessToken: data['accessToken'].toString(),
        refreshToken: data['refreshToken'].toString(),
        user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      );

  Future<http.Response> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (_loggingOut || _ended) throw StateError('Session ended');
    var response = await _send(method, path, body: body);
    if (_loggingOut || _ended) throw StateError('Session ended');
    if (response.statusCode != 401) return response;
    await _refreshOnce();
    if (_loggingOut || _ended) throw StateError('Session ended');
    response = await _send(method, path, body: body);
    if (_loggingOut || _ended) throw StateError('Session ended');
    return response;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) {
    final uri = Uri.parse('$serverUrl/api/v1$path');
    final headers = {
      'Authorization': 'Bearer $_accessToken',
      'Content-Type': 'application/json',
    };
    final encodedBody = body == null ? null : jsonEncode(body);
    return switch (method) {
      'GET' => http.get(uri, headers: headers),
      'POST' => http.post(uri, headers: headers, body: encodedBody),
      'PATCH' => http.patch(uri, headers: headers, body: encodedBody),
      'DELETE' => http.delete(uri, headers: headers),
      _ => throw ArgumentError('Unsupported HTTP method: $method'),
    };
  }

  Future<void> _refreshOnce() async {
    final existing = _refreshInProgress;
    if (existing != null) return existing;
    final operation = _refresh();
    _refreshInProgress = operation;
    try {
      await operation;
    } finally {
      _refreshInProgress = null;
    }
  }

  Future<void> _refresh() async {
    final response = await http.post(
      Uri.parse('$serverUrl/api/v1/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': _refreshToken}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError('Session expired');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _accessToken = data['accessToken'].toString();
    _refreshToken = data['refreshToken'].toString();
    user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await _persist();
  }

  Future<void> _persist() async {
    await _storage.write(key: _accessTokenKey, value: _accessToken);
    await _storage.write(key: _refreshTokenKey, value: _refreshToken);
  }

  // False means local credentials were cleared, but server revocation could not
  // be confirmed. The UI must report this rather than promise a global logout.
  Future<bool> logout({bool allDevices = false}) async {
    if (_loggingOut || _ended) return false;
    _loggingOut = true;
    try {
      final refresh = _refreshInProgress;
      if (refresh != null) {
        try {
          await refresh;
        } catch (_) {
          // Retry with the remaining credentials.
        }
      }
      final scope = allDevices ? 'global' : 'local';
      Future<http.Response> revoke() => http
          .post(
            Uri.parse('$serverUrl/api/v1/auth/logout?scope=$scope'),
            headers: {'Authorization': 'Bearer $_accessToken'},
          )
          .timeout(const Duration(seconds: 15));
      var response = await revoke();
      if (response.statusCode == 401) {
        await _refresh();
        response = await revoke();
      }
      return response.statusCode == 204;
    } catch (_) {
      return false;
    } finally {
      await _clearLocalSession();
    }
  }

  Future<void> _clearLocalSession() async {
    _ended = true;
    _accessToken = '';
    _refreshToken = '';
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
