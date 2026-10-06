import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/api_client.dart';
import 'package:todonote/data/api_config.dart';
import 'package:todonote/data/api_exception.dart';
import 'package:todonote/data/remote/api_client_dio.dart';

void main() {
  test('foreground and sync clients share the same API deployment', () {
    final syncClient = ApiClientDio.instance;
    final syncUri = ApiConfig.resolveApiUri('/sync/changes');

    expect(
      syncUri.toString(),
      'https://todosnotes.onrender.com/api/v1/sync/changes',
    );
    expect(ApiClient.baseUrl, ApiConfig.apiBaseUrl);
    expect(syncClient.apiBaseUri, ApiConfig.apiBaseUri);
    expect(syncClient.healthUri.host, syncUri.host);
    expect(ApiConfig.healthUri.host, syncUri.host);
  });

  test(
    '503 preserves sync_unavailable, request_id, and raw response',
    () async {
      final client = _errorClient(
        statusCode: 503,
        data: {'error': 'sync_unavailable', 'request_id': 'request-503'},
        maxAttempts: 1,
      );

      await expectLater(
        client.get('/sync/changes'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having((error) => error.code, 'code', 'sync_unavailable')
              .having((error) => error.requestId, 'requestId', 'request-503')
              .having(
                (error) => error.rawResponse,
                'rawResponse',
                containsPair('error', 'sync_unavailable'),
              ),
        ),
      );
    },
  );

  test('500 preserves sync_failed and request_id', () async {
    final client = _errorClient(
      statusCode: 500,
      data: {'error': 'sync_failed', 'request_id': 'request-500'},
      maxAttempts: 1,
    );

    await expectLater(
      client.get('/sync/changes'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'sync_failed')
            .having((error) => error.requestId, 'requestId', 'request-500'),
      ),
    );
  });

  test('503 is retried and the next successful response is returned', () async {
    var requests = 0;
    final dio = Dio(BaseOptions(baseUrl: ApiConfig.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          if (requests == 1) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: options,
                  statusCode: 503,
                  data: {
                    'error': 'sync_unavailable',
                    'request_id': 'retry-once',
                  },
                ),
              ),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'ok': true},
            ),
          );
        },
      ),
    );
    final client = ApiClientDio.forTesting(
      dio,
      sleeper: (_) async {},
      randomDouble: () => 0,
    );

    expect(await client.get('/sync/changes'), {'ok': true});
    expect(requests, 2);
  });

  test('Retry-After controls the retry delay', () async {
    var requests = 0;
    final delays = <Duration>[];
    final dio = Dio(BaseOptions(baseUrl: ApiConfig.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          if (requests == 1) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: options,
                  statusCode: 429,
                  data: {'error': 'rate_limited'},
                  headers: Headers.fromMap({
                    'retry-after': ['2'],
                  }),
                ),
              ),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'ok': true},
            ),
          );
        },
      ),
    );
    final client = ApiClientDio.forTesting(
      dio,
      sleeper: (delay) async => delays.add(delay),
      randomDouble: () => 0,
    );

    expect(await client.get('/sync/changes'), {'ok': true});
    expect(delays, [const Duration(seconds: 2)]);
  });

  test(
    'non-JSON 503 remains diagnosable instead of becoming unknown',
    () async {
      final client = _errorClient(
        statusCode: 503,
        data: '<html>Service Suspended</html>',
        maxAttempts: 1,
      );

      await expectLater(
        client.get('/sync/changes'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 'http_503')
              .having(
                (error) => error.rawResponse,
                'rawResponse',
                contains('Service Suspended'),
              ),
        ),
      );
    },
  );

  test('transient retry is capped at three total attempts', () async {
    var requests = 0;
    final dio = Dio(BaseOptions(baseUrl: ApiConfig.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: 503,
                data: {'error': 'sync_unavailable'},
              ),
            ),
          );
        },
      ),
    );
    final client = ApiClientDio.forTesting(
      dio,
      sleeper: (_) async {},
      randomDouble: () => 0,
    );

    await expectLater(
      client.get('/sync/changes'),
      throwsA(isA<ApiException>()),
    );
    expect(requests, 3);
  });

  test('401 is not retried', () async {
    var requests = 0;
    final dio = Dio(BaseOptions(baseUrl: ApiConfig.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: 401,
                data: {'error': 'unauthorized'},
              ),
            ),
          );
        },
      ),
    );
    final client = ApiClientDio.forTesting(
      dio,
      sleeper: (_) async {},
      randomDouble: () => 0,
    );

    await expectLater(
      client.get('/sync/changes'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.code, 'code', 'unauthorized'),
      ),
    );
    expect(requests, 1);
  });
}

ApiClientDio _errorClient({
  required int statusCode,
  required Object data,
  int maxAttempts = 3,
}) {
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.apiBaseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: options,
              statusCode: statusCode,
              data: data,
            ),
          ),
        );
      },
    ),
  );
  return ApiClientDio.forTesting(
    dio,
    sleeper: (_) async {},
    randomDouble: () => 0,
    maxAttempts: maxAttempts,
  );
}
