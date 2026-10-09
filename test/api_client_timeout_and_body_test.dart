import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todonote/data/api_client.dart';
import 'package:todonote/data/api_exception.dart';
import 'package:todonote/data/auth_storage.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'jwt-123'});
    await AuthStorage.instance.init();
  });

  tearDown(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await AuthStorage.instance.init();
  });

  group('DELETE with a JSON body', () {
    test('sends the body, content type and the auth header', () async {
      late http.Request seen;
      final client = ApiClient.forTesting(
        MockClient((request) async {
          seen = request;
          return _json({'ok': true, 'deleted': 1});
        }),
      );

      final result = await client.delete(
        '/devices',
        body: {'registrationId': 'abc'},
      );

      expect(seen.method, 'DELETE');
      expect(seen.url.path, endsWith('/api/v1/devices'));
      expect(jsonDecode(seen.body), {'registrationId': 'abc'});
      expect(seen.headers['content-type'], contains('application/json'));
      expect(seen.headers['Authorization'], 'Bearer jwt-123');
      expect(result, {'ok': true, 'deleted': 1});
    });

    test('without a body nothing changes: no body, no content type', () async {
      late http.Request seen;
      final client = ApiClient.forTesting(
        MockClient((request) async {
          seen = request;
          return http.Response('', 204);
        }),
      );

      await client.delete('/todos/1');

      expect(seen.method, 'DELETE');
      expect(seen.body, isEmpty);
      expect(seen.headers.containsKey('content-type'), isFalse);
    });
  });

  group('per-call timeout', () {
    test('a request that never answers fails with a retryable error', () async {
      final neverAnswers = Completer<http.Response>();
      final client = ApiClient.forTesting(
        MockClient((_) => neverAnswers.future),
      );

      await expectLater(
        client.post(
          '/devices',
          body: {'registrationId': 'abc'},
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'no_connection')
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });

    test('delete honours the timeout too', () async {
      final neverAnswers = Completer<http.Response>();
      final client = ApiClient.forTesting(
        MockClient((_) => neverAnswers.future),
      );

      await expectLater(
        client.delete(
          '/devices',
          body: {'registrationId': 'abc'},
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('a request that answers in time is unaffected', () async {
      final client = ApiClient.forTesting(
        MockClient((_) async => _json({'ok': true})),
      );

      final result = await client.post(
        '/devices',
        body: {'x': 1},
        timeout: const Duration(seconds: 5),
      );

      expect(result, {'ok': true});
    });

    test('without a timeout a slow answer still completes', () async {
      final client = ApiClient.forTesting(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return _json({'ok': true});
        }),
      );

      expect(await client.post('/devices', body: {'x': 1}), {'ok': true});
    });
  });
}
