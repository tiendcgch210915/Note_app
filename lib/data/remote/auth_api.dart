import 'dart:convert';

import '../auth_storage.dart';
import 'api_client_dio.dart';

/// Auth operations via Dio client. Supplements the existing AuthRepository
/// (which uses the http client) by providing token-decode utilities and a
/// Dio-backed re-auth path used by SyncWorker after a 401.
class AuthApiDio {
  AuthApiDio._();
  static final AuthApiDio instance = AuthApiDio._();

  final ApiClientDio _client = ApiClientDio.instance;

  /// Login and store token + user_id.
  Future<Map<String, dynamic>> login(String email, String password) async {
    final resp = await _client.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    final map = resp as Map<String, dynamic>;
    final token = map['token'] as String;
    final userMap = map['user'] as Map<String, dynamic>;
    await AuthStorage.instance.saveToken(token);
    await AuthStorage.instance.saveUserJson(userMap);
    return userMap;
  }

  /// Register and store token + user_id.
  Future<Map<String, dynamic>> register(
    String email,
    String password,
    String displayName,
  ) async {
    final resp = await _client.post(
      '/auth/register',
      data: {'email': email, 'password': password, 'display_name': displayName},
    );
    final map = resp as Map<String, dynamic>;
    final token = map['token'] as String;
    final userMap = map['user'] as Map<String, dynamic>;
    await AuthStorage.instance.saveToken(token);
    await AuthStorage.instance.saveUserJson(userMap);
    return userMap;
  }

  /// Decode JWT payload (base64url) to extract the `sub` field (user_id).
  /// Returns null if the token is missing or malformed.
  static String? decodeUserId(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      // Base64url → base64 standard (pad to multiple of 4)
      var payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return map['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Returns the current authenticated user_id from the stored token.
  String? get currentUserId {
    return decodeUserId(AuthStorage.instance.currentToken);
  }
}
