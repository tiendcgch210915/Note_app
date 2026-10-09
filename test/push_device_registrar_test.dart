import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/api_exception.dart';
import 'package:todonote/push/push_device_registrar.dart';
import 'package:todonote/push/push_registration_service.dart';

const _noConnection = ApiException(0, 'no_connection', 'offline');

class _FakeApi implements PushDevicesApi {
  final List<PushRegistrationId> registered = [];
  final List<String> unregistered = [];
  Future<void> Function(PushRegistrationId id)? onRegister;
  Future<void> Function(String id)? onUnregister;

  @override
  Future<void> register(PushRegistrationId id) {
    registered.add(id);
    return onRegister?.call(id) ?? Future<void>.value();
  }

  @override
  Future<void> unregister(String registrationId) {
    unregistered.add(registrationId);
    return onUnregister?.call(registrationId) ?? Future<void>.value();
  }
}

class _Env {
  _Env({Duration logoutWait = const Duration(milliseconds: 60)}) {
    registration = PushRegistrationService(
      getToken: () async => token,
      onTokenRefresh: () => refresh.stream,
    );
    registrar = PushDeviceRegistrar(
      api: api,
      registration: registration,
      authenticated: auth,
      addLogoutHook: logoutHooks.add,
      onlineChanges: () => online.stream,
      delay: (duration) {
        delays.add(duration);
        return delayGate?.future ?? Future<void>.value();
      },
      logoutWait: logoutWait,
      logger: logs.add,
    );
  }

  final api = _FakeApi();
  final auth = ValueNotifier<bool>(true);
  final refresh = StreamController<String>.broadcast();
  final online = StreamController<bool>.broadcast();
  final logoutHooks = <Future<void> Function()>[];
  final delays = <Duration>[];
  final logs = <String>[];
  Completer<void>? delayGate;
  String? token = 'tok-1';
  late final PushRegistrationService registration;
  late final PushDeviceRegistrar registrar;

  List<String> get registeredValues =>
      api.registered.map((id) => id.value).toList();

  /// Cho các vòng thử lại bất đồng bộ chạy hết trong khả năng của chúng.
  Future<void> pump() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> dispose() async {
    await refresh.close();
    await online.close();
  }
}

void main() {
  late _Env env;

  setUp(() => env = _Env());
  tearDown(() => env.dispose());

  group('registering', () {
    test('POSTs the token once the device has one', () async {
      env.registrar.attach();

      await env.registration.start();
      await env.pump();

      expect(env.api.registered, [
        const PushRegistrationId(
          value: 'tok-1',
          kind: PushRegistrationKind.token,
        ),
      ]);
      expect(env.api.registered.single.kindName, 'token');
    });

    test('registers again when FCM refreshes the token', () async {
      env.registrar.attach();
      await env.registration.start();
      await env.pump();

      env.refresh.add('tok-2');
      await env.pump();

      expect(env.registeredValues, ['tok-1', 'tok-2']);
    });

    test('does not repeat the call for an id the server already has', () async {
      env.registrar.attach();
      await env.registration.start();
      await env.pump();

      env.refresh
        ..add('tok-1')
        ..add('tok-1');
      await env.pump();

      expect(env.registeredValues, ['tok-1']);
    });

    test('picks up an id that was emitted before attach()', () async {
      await env.registration.start();
      await env.pump();

      env.registrar.attach();
      await env.pump();

      expect(env.registeredValues, ['tok-1']);
    });

    test('attach twice does not double-register', () async {
      env.registrar
        ..attach()
        ..attach();

      await env.registration.start();
      await env.pump();

      expect(env.registeredValues, ['tok-1']);
      expect(env.logoutHooks, hasLength(1));
    });

    test('does nothing while signed out, works again after sign-in', () async {
      env.auth.value = false;
      env.registrar.attach();

      await env.registration.start();
      await env.pump();
      expect(env.api.registered, isEmpty);

      env.auth.value = true;
      await env.registration.stop();
      await env.registration.start();
      await env.pump();
      expect(env.registeredValues, ['tok-1']);
    });

    test(
      'a new login re-registers the same id (server row was deleted)',
      () async {
        env.registrar.attach();
        await env.registration.start();
        await env.pump();

        env.auth.value = false; // đăng xuất
        await env.registration.stop();
        env.auth.value = true; // đăng nhập lại
        await env.registration.start();
        await env.pump();

        expect(env.registeredValues, ['tok-1', 'tok-1']);
      },
    );
  });

  group('retrying', () {
    test(
      'backs off between attempts and stops after the first success',
      () async {
        var calls = 0;
        env.api.onRegister = (_) async {
          if (++calls <= 2) throw _noConnection;
        };
        env.registrar.attach();

        await env.registration.start();
        await env.pump();

        expect(env.api.registered, hasLength(3));
        expect(env.delays, const [Duration(seconds: 5), Duration(seconds: 15)]);
      },
    );

    test(
      'honours Retry-After but never below the backoff or above the cap',
      () async {
        final hints = <Duration?>[
          const Duration(seconds: 30), // lớn hơn backoff → dùng 30s
          const Duration(seconds: 1), // nhỏ hơn backoff → dùng 15s
          const Duration(minutes: 10), // vượt trần → 2 phút
        ];
        var calls = 0;
        env.api.onRegister = (_) async {
          if (calls < hints.length) {
            throw ApiException(
              429,
              'rate_limited',
              'slow',
              retryAfter: hints[calls++],
            );
          }
        };
        env.registrar.attach();

        await env.registration.start();
        await env.pump();

        expect(env.delays, const [
          Duration(seconds: 30),
          Duration(seconds: 15),
          Duration(minutes: 2),
        ]);
      },
    );

    test(
      'retries 5xx, parse errors (server waking up) and unknown network errors',
      () async {
        final failures = <Object>[
          const ApiException(503, 'sync_unavailable', 'waking'),
          const ApiException(0, 'response_parse_error', 'html page'),
          StateError('tls handshake'),
        ];
        var calls = 0;
        env.api.onRegister = (_) async {
          if (calls < failures.length) throw failures[calls++];
        };
        env.registrar.attach();

        await env.registration.start();
        await env.pump();

        expect(env.api.registered, hasLength(4));
      },
    );

    for (final status in [400, 401, 403, 404]) {
      test('does not retry HTTP $status', () async {
        env.api.onRegister = (_) async =>
            throw ApiException(status, 'http_$status', 'no');
        env.registrar.attach();

        await env.registration.start();
        await env.pump();

        expect(env.api.registered, hasLength(1));
        expect(env.delays, isEmpty);
      });
    }

    test(
      'gives up after maxAttempts, then retries when the network is back',
      () async {
        var failing = true;
        env.api.onRegister = (_) async {
          if (failing) throw _noConnection;
        };
        env.registrar.attach();

        await env.registration.start();
        await env.pump();

        expect(env.api.registered, hasLength(PushDeviceRegistrar.maxAttempts));
        expect(env.delays, PushDeviceRegistrar.backoff);

        env.online.add(false); // vẫn offline: không làm gì
        await env.pump();
        expect(env.api.registered, hasLength(PushDeviceRegistrar.maxAttempts));

        failing = false;
        env.online.add(true);
        await env.pump();

        expect(
          env.api.registered,
          hasLength(PushDeviceRegistrar.maxAttempts + 1),
        );
      },
    );

    test('a pending retry stops when the user signs out', () async {
      env.delayGate = Completer<void>();
      env.api.onRegister = (_) async => throw _noConnection;
      env.registrar.attach();
      await env.registration.start();
      await env.pump();
      expect(env.api.registered, hasLength(1)); // đang chờ backoff

      env.auth.value = false;
      env.delayGate!.complete();
      await env.pump();

      expect(env.api.registered, hasLength(1));
    });

    test('a newer id replaces a retry loop that is still waiting', () async {
      env.delayGate = Completer<void>();
      var failFirst = true;
      env.api.onRegister = (id) async {
        if (id.value == 'tok-1' && failFirst) throw _noConnection;
      };
      env.registrar.attach();
      await env.registration.start();
      await env.pump();

      env.refresh.add('tok-2');
      await env.pump();
      env.delayGate!.complete();
      await env.pump();

      expect(
        env.registeredValues.where((v) => v == 'tok-1'),
        hasLength(1),
        reason: 'vòng cũ phải dừng, không gọi lại tok-1',
      );
      expect(env.registeredValues.last, 'tok-2');
    });

    test('going online after sign-out does nothing', () async {
      env.api.onRegister = (_) async => throw _noConnection;
      env.registrar.attach();
      await env.registration.start();
      await env.pump();
      final before = env.api.registered.length;

      env.auth.value = false;
      env.online.add(true);
      await env.pump();

      expect(env.api.registered, hasLength(before));
    });
  });

  group('logging out', () {
    test('DELETEs the current registration', () async {
      env.registrar.attach();
      await env.registration.start();
      await env.pump();

      await env.registrar.unregisterCurrent();

      expect(env.api.unregistered, ['tok-1']);
    });

    test('registers itself as a logout hook', () async {
      env.registrar.attach();

      expect(env.logoutHooks, [env.registrar.unregisterCurrent]);
    });

    test('does nothing when the device has no id', () async {
      env.token = null;
      env.registrar.attach();
      await env.registration.start();
      await env.pump();

      await env.registrar.unregisterCurrent();

      expect(env.api.unregistered, isEmpty);
    });

    test('failures never throw: offline, server error, unexpected', () async {
      env.registrar.attach();
      await env.registration.start();
      await env.pump();

      for (final failure in <Object>[
        _noConnection,
        const ApiException(500, 'server_error', 'boom'),
        StateError('weird'),
      ]) {
        env.api.onUnregister = (_) async => throw failure;
        await env.registrar.unregisterCurrent();
      }

      expect(env.api.unregistered, hasLength(3));
    });

    test('a hanging server does not hold the logout past logoutWait', () async {
      env.registrar.attach();
      await env.registration.start();
      await env.pump();
      env.api.onUnregister = (_) =>
          Completer<void>().future; // không bao giờ xong

      await env.registrar.unregisterCurrent().timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('unregisterCurrent bị treo'),
      );

      expect(env.api.unregistered, ['tok-1']);
    });

    test('the DELETE is issued synchronously, before any await', () async {
      env.registrar.attach();
      await env.registration.start();
      await env.pump();

      // Không await: DELETE phải đã được phát (token còn trong AuthStorage).
      final done = env.registrar.unregisterCurrent();

      expect(env.api.unregistered, ['tok-1']);
      await done;
    });

    test('a token refresh during logout is not registered', () async {
      env.registrar.attach();
      await env.registration.start();
      await env.pump();
      env.api.onUnregister = (_) => Completer<void>().future;

      final logout = env.registrar.unregisterCurrent();
      env.refresh.add('tok-2');
      await env.pump();
      await logout;

      expect(env.registeredValues, ['tok-1']);
    });

    test('a retry loop in progress is cancelled by logout', () async {
      env.delayGate = Completer<void>();
      env.api.onRegister = (_) async => throw _noConnection;
      env.registrar.attach();
      await env.registration.start();
      await env.pump();

      await env.registrar.unregisterCurrent();
      env.delayGate!.complete();
      await env.pump();

      expect(env.api.registered, hasLength(1));
    });

    test('after logout and a new login the device registers again', () async {
      env.registrar.attach();
      await env.registration.start();
      await env.pump();

      await env.registrar.unregisterCurrent();
      env.auth.value = false; // AuthStorage.clear()
      await env.registration.stop();
      env.auth.value = true;
      await env.registration.start();
      await env.pump();

      expect(env.registeredValues, ['tok-1', 'tok-1']);
    });
  });

  test('log lines never contain the registration id', () async {
    var calls = 0;
    env.api.onRegister = (_) async {
      if (++calls <= 2) throw _noConnection;
    };
    env.registrar.attach();

    await env.registration.start();
    await env.pump();
    env.refresh.add('tok-2');
    await env.pump();
    await env.registrar.unregisterCurrent();

    expect(env.logs, isNotEmpty);
    for (final line in env.logs) {
      expect(line, isNot(contains('tok-1')));
      expect(line, isNot(contains('tok-2')));
    }
  });
}
