import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate, SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
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
  ApiClient._({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static final ApiClient instance = ApiClient._();

  @visibleForTesting
  factory ApiClient.forTesting(http.Client httpClient) =>
      ApiClient._(httpClient: httpClient);

  /// CONFIGURE TRƯỚC KHI BUILD:
  /// - Android emulator: 'http://10.0.2.2:3000'
  /// - iOS simulator: 'http://localhost:3000'
  /// - Real device: thay bằng IP máy chủ (vd 'http://192.168.1.5:3000')
  static String get baseUrl => ApiConfig.apiBaseUrl;

  /// Health probe endpoint (không qua /api/v1 prefix).
  static String get healthUrl => ApiConfig.healthUrl;

  final http.Client _http;

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
    final uri = path.startsWith('http')
        ? Uri.parse(path)
        : ApiConfig.resolveApiUri(path);
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

  /// [timeout] (tuỳ chọn) giới hạn thời gian chờ phản hồi của riêng lời gọi này.
  /// Hết giờ → `ApiException('no_connection')`, tức loại lỗi có thể thử lại.
  /// Mặc định không giới hạn, giữ nguyên hành vi cũ của các lời gọi khác.
  Future<dynamic> post(
    String path, {
    Object? body,
    bool requireAuth = true,
    Duration? timeout,
  }) async {
    return _send(
      'POST',
      path,
      body: body,
      requireAuth: requireAuth,
      timeout: timeout,
    );
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

  /// [body] (tuỳ chọn) cho các endpoint DELETE nhận JSON body (ví dụ
  /// `DELETE /devices`). Không có body thì không gửi `Content-Type`, như trước.
  Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool requireAuth = true,
    Duration? timeout,
  }) async {
    return _send(
      'DELETE',
      path,
      query: query,
      body: body,
      requireAuth: requireAuth,
      timeout: timeout,
    );
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool requireAuth = true,
    Duration? timeout,
  }) async {
    final uri = _buildUri(path, query);
    final encodedBody = body == null ? null : jsonEncode(body);
    final headers = _headers(
      requireAuth: requireAuth,
      hasBody: encodedBody != null,
    );
    debugPrint('[ApiClient] $method $uri');

    try {
      final Future<http.Response> pending;
      switch (method) {
        case 'GET':
          pending = _http.get(uri, headers: headers);
          break;
        case 'POST':
          pending = _http.post(uri, headers: headers, body: encodedBody);
          break;
        case 'PATCH':
          pending = _http.patch(uri, headers: headers, body: encodedBody);
          break;
        case 'PUT':
          pending = _http.put(uri, headers: headers, body: encodedBody);
          break;
        case 'DELETE':
          pending = _http.delete(uri, headers: headers, body: encodedBody);
          break;
        default:
          throw ApiException(0, 'unknown', 'Unsupported method $method');
      }
      final resp = await (timeout == null ? pending : pending.timeout(timeout));

      // 204 No Content
      if (resp.statusCode == 204) return null;

      // Success 2xx
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (resp.body.isEmpty) return null;
        return jsonDecode(resp.body);
      }

      final errorBody = _decodeErrorBody(resp.body);
      throw ApiException.fromResponse(
        resp.statusCode,
        errorBody,
        rawResponse: _safeRawResponse(resp.body),
        retryAfter: _parseRetryAfter(resp.headers['retry-after']),
      );
    } on SocketException {
      throw const ApiException(0, 'no_connection', 'Không có kết nối mạng');
    } on TimeoutException {
      throw const ApiException(0, 'no_connection', 'Yêu cầu hết thời gian chờ');
    } on FormatException catch (e) {
      throw ApiException(
        0,
        'response_parse_error',
        'Phản hồi không hợp lệ: ${e.message}',
      );
    }
  }

  /// Health probe (không qua prefix /api/v1).
  Future<bool> healthCheck() async {
    try {
      final uri = ApiConfig.healthUri;
      debugPrint('[ApiClient] GET $uri');
      final resp = await _http.get(uri).timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _http.close();

  static Map<String, dynamic> _decodeErrorBody(String body) {
    if (body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return const {};
    }
  }

  static Object? _safeRawResponse(String body) {
    final decoded = _decodeErrorBody(body);
    if (decoded.isNotEmpty) {
      const sensitiveKeys = {
        'authorization',
        'token',
        'access_token',
        'refresh_token',
        'password',
      };
      return decoded.map(
        (key, value) => MapEntry(
          key,
          sensitiveKeys.contains(key.toLowerCase()) ? '[redacted]' : value,
        ),
      );
    }
    const maxLength = 2000;
    return body.length <= maxLength
        ? body
        : '${body.substring(0, maxLength)}...';
  }

  static Duration? _parseRetryAfter(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return Duration(seconds: seconds.clamp(0, 86400));
    try {
      final date = HttpDate.parse(value);
      final duration = date.difference(DateTime.now().toUtc());
      return duration.isNegative ? Duration.zero : duration;
    } catch (_) {
      return null;
    }
  }
}
