import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api_config.dart';
import '../api_exception.dart';
import '../auth_storage.dart';

/// ValueNotifier that fires when a 401 is received, signalling the app to
/// return to the login screen.
final needsReLoginNotifier = StreamController<void>.broadcast();

/// Dio-based HTTP client used exclusively by [SyncWorker] for sync endpoints.
///
/// Features:
///  - Auto-attach `Authorization: Bearer <token>` via interceptor
///  - 401 → clear token + emit re-login signal
///  - Timeouts: connect 10s, receive 30s
///  - Base URL same as [ApiClient]
class ApiClientDio {
  ApiClientDio._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
        responseType: ResponseType.json,
      ),
    );
    _dio.interceptors.add(_AuthInterceptor());
    _dio.interceptors.add(_SanitizedRequestLogInterceptor());
  }

  static final ApiClientDio instance = ApiClientDio._();
  ApiClientDio.forTesting(
    this._dio, {
    Future<void> Function(Duration duration)? sleeper,
    double Function()? randomDouble,
    int maxAttempts = 3,
  }) : _sleep = sleeper ?? Future<void>.delayed,
       _randomDouble = randomDouble ?? Random().nextDouble,
       _maxAttempts = maxAttempts;

  late final Dio _dio;
  Future<void> Function(Duration duration) _sleep = Future<void>.delayed;
  double Function() _randomDouble = Random().nextDouble;
  int _maxAttempts = 3;

  Dio get dio => _dio;
  Uri get apiBaseUri => Uri.parse(_dio.options.baseUrl);
  Uri get healthUri => apiBaseUri.replace(path: '/health', query: null);

  // ─── Convenience wrappers ─────────────────────────────────────────

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) =>
      _request(
        () => _dio.get(_normalizePath(path), queryParameters: queryParameters),
      );

  Future<dynamic> post(String path, {dynamic data}) =>
      _request(() => _dio.post(_normalizePath(path), data: data));

  Future<dynamic> patch(String path, {dynamic data}) =>
      _request(() => _dio.patch(_normalizePath(path), data: data));

  Future<dynamic> delete(String path) =>
      _request(() => _dio.delete(_normalizePath(path)));

  Future<dynamic> _request(Future<Response<dynamic>> Function() send) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final response = await send();
        return response.data;
      } on DioException catch (error) {
        final exception = _wrapDio(error);
        if (!exception.isRetryable || attempt >= _maxAttempts) {
          throw exception;
        }
        final delay = _retryDelay(attempt, exception.retryAfter);
        debugPrint(
          '[ApiClientDio] retry attempt=${attempt + 1}/$_maxAttempts '
          'after=${delay.inMilliseconds}ms status=${exception.statusCode} '
          'code=${exception.code}'
          '${exception.requestId == null ? '' : ' request_id=${exception.requestId}'}',
        );
        await _sleep(delay);
      }
    }
  }

  // ─── DioException → ApiException ─────────────────────────────────

  static ApiException _wrapDio(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return ApiException(
        0,
        'timeout',
        e.message ?? 'Request timed out',
        rawResponse: e.error?.toString(),
      );
    }
    if (e.type == DioExceptionType.connectionError) {
      return ApiException(
        0,
        'no_connection',
        e.message ?? 'Connection failed',
        rawResponse: e.error?.toString(),
      );
    }
    if (e.type == DioExceptionType.cancel) {
      return ApiException(0, 'cancelled', e.message ?? 'Request cancelled');
    }
    if (e.type == DioExceptionType.badCertificate) {
      return ApiException(
        0,
        'tls_error',
        e.message ?? 'TLS certificate rejected',
      );
    }
    final resp = e.response;
    if (resp == null) {
      return ApiException(
        0,
        'network_error',
        e.message ?? 'Network request failed',
        rawResponse: e.error?.toString(),
      );
    }
    final status = resp.statusCode ?? 0;
    final rawResponse = _safeRawResponse(resp.data);
    final body = _decodeErrorBody(resp.data);
    return ApiException.fromResponse(
      status,
      body,
      rawResponse: rawResponse,
      retryAfter: _parseRetryAfter(resp.headers.value('retry-after')),
    );
  }

  Duration _retryDelay(int failedAttempt, Duration? retryAfter) {
    if (retryAfter != null) return retryAfter;
    final exponentialMs = 250 * (1 << (failedAttempt - 1).clamp(0, 4));
    final jitterMs = (exponentialMs * 0.5 * _randomDouble()).round();
    return Duration(milliseconds: exponentialMs + jitterMs);
  }

  static String _normalizePath(String path) =>
      path.startsWith('/') ? path.substring(1) : path;

  static Map<String, dynamic> _decodeErrorBody(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }

  static Object? _safeRawResponse(Object? data) {
    if (data == null || data is num || data is bool) return data;
    if (data is Map) return _sanitizeMap(data);
    final text = data is String ? data : data.toString();
    const maxLength = 2000;
    return text.length <= maxLength
        ? text
        : '${text.substring(0, maxLength)}...';
  }

  static Map<String, dynamic> _sanitizeMap(Map<dynamic, dynamic> value) {
    const sensitiveKeys = {
      'authorization',
      'token',
      'access_token',
      'refresh_token',
      'password',
    };
    return value.map((key, item) {
      final stringKey = key.toString();
      if (sensitiveKeys.contains(stringKey.toLowerCase())) {
        return MapEntry(stringKey, '[redacted]');
      }
      if (item is Map) return MapEntry(stringKey, _sanitizeMap(item));
      if (item is List) {
        return MapEntry(
          stringKey,
          item
              .map((entry) => entry is Map ? _sanitizeMap(entry) : entry)
              .toList(),
        );
      }
      return MapEntry(stringKey, item);
    });
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

/// Dio interceptor that attaches JWT and handles 401 globally.
class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = AuthStorage.instance.currentToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Clear stale token and signal the app to show login screen
      await AuthStorage.instance.clear();
      needsReLoginNotifier.add(null);
    }
    handler.next(err);
  }
}

class _SanitizedRequestLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[ApiClientDio] ${options.method} ${options.uri}');
    handler.next(options);
  }
}
