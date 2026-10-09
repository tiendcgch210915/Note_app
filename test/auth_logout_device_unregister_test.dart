import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todonote/data/api_client.dart';
import 'package:todonote/data/auth_repository.dart';
import 'package:todonote/data/auth_storage.dart';
import 'package:todonote/push/push_device_registrar.dart';
import 'package:todonote/push/push_registration_service.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `AuthRepository.instance` dựng ApiClient thật nên phải gán trong vùng test
  // (setUp), không được chạm tới ở `main()`.
  late AuthRepository repo;
  const defaultHookTimeout = Duration(seconds: 5);

  setUp(() async {
    repo = AuthRepository.instance;
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'jwt-123',
      'auth_user': '{"id":"u1"}',
    });
    await AuthStorage.instance.init();
  });

  tearDown(() async {
    repo.beforeLogoutTimeout = defaultHookTimeout;
    FlutterSecureStorage.setMockInitialValues({});
    await AuthStorage.instance.init();
  });

  group('AuthRepository.logout hooks', () {
    test(
      'run while the session is still valid, then the session is cleared',
      () async {
        String? tokenSeenByHook;
        Future<void> hook() async =>
            tokenSeenByHook = AuthStorage.instance.currentToken;
        repo.addBeforeLogoutHook(hook);
        addTearDown(() => repo.removeBeforeLogoutHook(hook));

        await repo.logout();

        expect(tokenSeenByHook, 'jwt-123');
        expect(AuthStorage.instance.currentToken, isNull);
        expect(AuthStorage.instance.authenticated.value, isFalse);
      },
    );

    test('a failing hook does not block the logout or the next hook', () async {
      var secondRan = false;
      Future<void> failing() async => throw StateError('boom');
      Future<void> second() async => secondRan = true;
      repo
        ..addBeforeLogoutHook(failing)
        ..addBeforeLogoutHook(second);
      addTearDown(() {
        repo
          ..removeBeforeLogoutHook(failing)
          ..removeBeforeLogoutHook(second);
      });

      await repo.logout();

      expect(secondRan, isTrue);
      expect(AuthStorage.instance.currentToken, isNull);
    });

    test('a hook that hangs is abandoned after the timeout', () async {
      repo.beforeLogoutTimeout = const Duration(milliseconds: 40);
      Future<void> hanging() => Completer<void>().future;
      repo.addBeforeLogoutHook(hanging);
      addTearDown(() => repo.removeBeforeLogoutHook(hanging));

      await repo.logout().timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('logout bị treo bởi hook'),
      );

      expect(AuthStorage.instance.currentToken, isNull);
    });

    test('adding the same hook twice runs it once', () async {
      var runs = 0;
      Future<void> hook() async => runs++;
      repo
        ..addBeforeLogoutHook(hook)
        ..addBeforeLogoutHook(hook);
      addTearDown(() => repo.removeBeforeLogoutHook(hook));

      await repo.logout();

      expect(runs, 1);
    });
  });

  group('logout unregisters the device (real ApiClient + AuthStorage)', () {
    late List<http.Request> requests;
    late Future<http.Response> Function(http.Request) handler;
    late PushDeviceRegistrar registrar;
    late PushRegistrationService registration;

    setUp(() async {
      requests = [];
      handler = (_) async => _json({'ok': true});
      final client = ApiClient.forTesting(
        MockClient((request) {
          requests.add(request);
          return handler(request);
        }),
      );
      registration = PushRegistrationService(
        getToken: () async => 'tok-1',
        onTokenRefresh: () => const Stream<String>.empty(),
      );
      registrar = PushDeviceRegistrar(
        api: PushDevicesApi(client: client),
        registration: registration,
        authenticated: AuthStorage.instance.authenticated,
        addLogoutHook: repo.addBeforeLogoutHook,
        onlineChanges: () => const Stream<bool>.empty(),
        logoutWait: const Duration(milliseconds: 80),
        logger: (_) {},
      )..attach();
      addTearDown(
        () => repo.removeBeforeLogoutHook(registrar.unregisterCurrent),
      );

      await registration.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });

    test('POST /devices carries the contract fields and the JWT', () {
      final post = requests.single;

      expect(post.method, 'POST');
      expect(post.url.path, endsWith('/api/v1/devices'));
      expect(post.headers['Authorization'], 'Bearer jwt-123');
      expect(jsonDecode(post.body), {
        'registrationId': 'tok-1',
        'kind': 'token',
        'platform': 'android',
      });
    });

    test(
      'DELETE /devices is sent with the JWT before the session is cleared',
      () async {
        await repo.logout();

        expect(requests.map((r) => r.method), ['POST', 'DELETE']);
        final delete = requests.last;
        expect(delete.url.path, endsWith('/api/v1/devices'));
        expect(delete.headers['Authorization'], 'Bearer jwt-123');
        expect(jsonDecode(delete.body), {'registrationId': 'tok-1'});
        expect(AuthStorage.instance.currentToken, isNull);
      },
    );

    test(
      'a slow server does not stall the logout, and the DELETE keeps its JWT',
      () async {
        handler = (request) {
          if (request.method == 'DELETE') {
            return Completer<http.Response>().future;
          }
          return Future.value(_json({'ok': true}));
        };

        await repo.logout().timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('logout bị treo vì server chậm'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(AuthStorage.instance.currentToken, isNull);
        final delete = requests.lastWhere((r) => r.method == 'DELETE');
        // Token đã bị xóa khi request còn đang chạy nền, nhưng header đã gắn từ trước.
        expect(delete.headers['Authorization'], 'Bearer jwt-123');
      },
    );

    test('being offline does not block the logout', () async {
      handler = (request) async {
        if (request.method == 'DELETE') throw const SocketException('offline');
        return _json({'ok': true});
      };

      await repo.logout();

      expect(AuthStorage.instance.currentToken, isNull);
    });

    test('a server error does not block the logout', () async {
      handler = (request) async => request.method == 'DELETE'
          ? _json({'error': 'server_error'}, 500)
          : _json({'ok': true});

      await repo.logout();

      expect(AuthStorage.instance.currentToken, isNull);
    });
  });
}
