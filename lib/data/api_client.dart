import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'auth_storage.dart';

/// HTTP client cho backend.
///
/// - Base URL trỏ tới /api/v1
/// - Auto-attach Authorization: Bearer `<token>` từ AuthStorage.currentToken
/// - Parse error JSON → throw ApiException
/// - 204 → trả null
/// - SocketException → throw ApiException('no_connection')
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  /// CONFIGURE TRƯỚC KHI BUILD:
  /// - Android emulator: 'http://10.0.2.2:3000'
  /// - iOS simulator: 'http://localhost:3000'
  /// - Real device: thay bằng IP máy chủ (vd 'http://192.168.1.5:3000')
  static const String baseUrl = 'https://todo-note-h8s1.onrender.com/api/v1';

  /// Health probe endpoint (không qua /api/v1 prefix).
  static const String healthUrl = 'https://todo-note-h8s1.onrender.com/health';

  final http.Client _http = http.Client();

  Map<String, String> _headers({
    bool requireAuth = true,
    bool hasBody = false,
  }) {
    final headers = <String, String>{
      // Only declare Content-Type when sending a body.
      // DELETE with Content-Type: application/json but no body triggers 400
      // on Express body-parser middleware (backend returns {"error":"Bad request"}).
      if (hasBody) 'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (requireAuth) {
      final token = AuthStorage.instance.currentToken;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Uri _buildUri(String path, [Map<String, dynamic>? query]) {
    final fullPath = path.startsWith('http') ? path : '$baseUrl$path';
    final uri = Uri.parse(fullPath);
    if (query == null || query.isEmpty) return uri;
    final queryParams = <String, String>{};
    query.forEach((k, v) {
      if (v == null) return;
      queryParams[k] = v.toString();
    });
    return uri.replace(
      queryParameters: {...uri.queryParameters, ...queryParams},
    );
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool requireAuth = true,
  }) async {
    return _send('GET', path, query: query, requireAuth: requireAuth);
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    bool requireAuth = true,
  }) async {
    return _send('POST', path, body: body, requireAuth: requireAuth);
  }

  Future<dynamic> patch(
    String path, {
    Object? body,
    bool requireAuth = true,
  }) async {
    return _send('PATCH', path, body: body, requireAuth: requireAuth);
  }

  Future<dynamic> put(
    String path, {
    Object? body,
    bool requireAuth = true,
  }) async {
    return _send('PUT', path, body: body, requireAuth: requireAuth);
  }

  Future<dynamic> delete(String path, {bool requireAuth = true}) async {
    return _send('DELETE', path, requireAuth: requireAuth);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool requireAuth = true,
  }) async {
    final uri = _buildUri(path, query);
    final encodedBody = body == null ? null : jsonEncode(body);
    final headers = _headers(
      requireAuth: requireAuth,
      hasBody: encodedBody != null,
    );

    try {
      late http.Response resp;
      switch (method) {
        case 'GET':
          resp = await _http.get(uri, headers: headers);
          break;
        case 'POST':
          resp = await _http.post(uri, headers: headers, body: encodedBody);
          break;
        case 'PATCH':
          resp = await _http.patch(uri, headers: headers, body: encodedBody);
          break;
        case 'PUT':
          resp = await _http.put(uri, headers: headers, body: encodedBody);
          break;
        case 'DELETE':
          resp = await _http.delete(uri, headers: headers);
          break;
        default:
          throw ApiException(0, 'unknown', 'Unsupported method $method');
      }

      // 204 No Content
      if (resp.statusCode == 204) return null;

      // Success 2xx
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (resp.body.isEmpty) return null;
        return jsonDecode(resp.body);
      }

      // 4xx — parse error
      if (resp.statusCode >= 400 && resp.statusCode < 500) {
        Map<String, dynamic> errorBody;
        try {
          errorBody = jsonDecode(resp.body) as Map<String, dynamic>;
        } catch (_) {
          errorBody = {'error': 'unknown'};
        }
        throw ApiException.fromResponse(resp.statusCode, errorBody);
      }

      // 5xx
      throw ApiException(
        resp.statusCode,
        'server_error',
        'Server error: ${resp.statusCode}',
      );
    } on SocketException {
      throw const ApiException(0, 'no_connection', 'Không có kết nối mạng');
    } on TimeoutException {
      throw const ApiException(0, 'no_connection', 'Yêu cầu hết thời gian chờ');
    } on FormatException catch (e) {
      throw ApiException(0, 'unknown', 'Phản hồi không hợp lệ: ${e.message}');
    }
  }

  /// Health probe (không qua prefix /api/v1).
  Future<bool> healthCheck() async {
    try {
      final uri = Uri.parse(healthUrl);
      final resp = await _http.get(uri).timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _http.close();
}
