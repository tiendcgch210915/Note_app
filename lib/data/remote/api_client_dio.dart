import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

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
        baseUrl: 'https://todo-note-h8s1.onrender.com/api/v1',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
        responseType: ResponseType.json,
      ),
    );
    _dio.interceptors.add(_AuthInterceptor());
  }

  static final ApiClientDio instance = ApiClientDio._();
  late final Dio _dio;

  Dio get dio => _dio;

  // ─── Convenience wrappers ─────────────────────────────────────────

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final resp = await _dio.get(path, queryParameters: queryParameters);
      return resp.data;
    } on DioException catch (e) {
      throw _wrapDio(e);
    }
  }

  Future<dynamic> post(String path, {dynamic data}) async {
    try {
      final resp = await _dio.post(path, data: data);
      return resp.data;
    } on DioException catch (e) {
      throw _wrapDio(e);
    }
  }

  Future<dynamic> patch(String path, {dynamic data}) async {
    try {
      final resp = await _dio.patch(path, data: data);
      return resp.data;
    } on DioException catch (e) {
      throw _wrapDio(e);
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      final resp = await _dio.delete(path);
      return resp.data;
    } on DioException catch (e) {
      throw _wrapDio(e);
    }
  }

  // ─── DioException → ApiException ─────────────────────────────────

  static ApiException _wrapDio(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const ApiException(0, 'no_connection', 'Không có kết nối mạng');
    }
    final resp = e.response;
    if (resp == null) {
      return ApiException(0, 'unknown', e.message ?? 'Unknown error');
    }
    final status = resp.statusCode ?? 0;
    Map<String, dynamic> body;
    try {
      if (resp.data is Map<String, dynamic>) {
        body = resp.data as Map<String, dynamic>;
      } else if (resp.data is String) {
        body = jsonDecode(resp.data as String) as Map<String, dynamic>;
      } else {
        body = {'error': 'unknown'};
      }
    } catch (_) {
      body = {'error': 'unknown'};
    }
    return ApiException.fromResponse(status, body);
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
