import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/push/push_registration_service.dart';

void main() {
  late StreamController<String> refresh;
  late List<String> log;
  late List<PushRegistrationId> emitted;
  late StreamSubscription<PushRegistrationId> listener;

  PushRegistrationService build({Future<String?> Function()? getToken}) {
    final service = PushRegistrationService(
      getToken:
          getToken ??
          () async {
            log.add('getToken');
            return 'token-1';
          },
      onTokenRefresh: () {
        log.add('onTokenRefresh');
        return refresh.stream;
      },
    );
    listener = service.registrationIds.listen(emitted.add);
    return service;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    refresh = StreamController<String>.broadcast();
    log = [];
    emitted = [];
  });

  tearDown(() async {
    await listener.cancel();
    await refresh.close();
  });

  test('emits the current token tagged as "token"', () async {
    final service = build();

    await service.start();
    await settle();

    expect(emitted, [
      const PushRegistrationId(
        value: 'token-1',
        kind: PushRegistrationKind.token,
      ),
    ]);
    expect(service.current, emitted.single);
    expect(service.current!.kindName, 'token');
  });

  test('listens for refreshes before asking for the token', () async {
    final service = build();

    await service.start();

    expect(log, ['onTokenRefresh', 'getToken']);
  });

  test('emits refreshed tokens and skips duplicates', () async {
    final service = build();
    await service.start();

    refresh
      ..add('token-2')
      ..add('token-2')
      ..add('token-1');
    await settle();

    expect(emitted.map((id) => id.value), ['token-1', 'token-2', 'token-1']);
  });

  test('a refresh that lands while getToken is pending is not overwritten by '
      'the stale result', () async {
    final pending = Completer<String?>();
    final service = build(getToken: () => pending.future);

    final started = service.start();
    refresh.add('fresh');
    await settle();
    pending.complete('stale');
    await started;
    await settle();

    expect(emitted.map((id) => id.value), ['fresh']);
    expect(service.current!.value, 'fresh');
  });

  test('calling start twice only fetches once', () async {
    final service = build();

    await service.start();
    await service.start();

    expect(log.where((entry) => entry == 'getToken'), hasLength(1));
    expect(log.where((entry) => entry == 'onTokenRefresh'), hasLength(1));
  });

  test('stop clears the value and ignores later refreshes', () async {
    final service = build();
    await service.start();

    await service.stop();
    refresh.add('after-stop');
    await settle();

    expect(service.current, isNull);
    expect(emitted.map((id) => id.value), ['token-1']);
  });

  test('start after stop emits the same token again (new login)', () async {
    final service = build();
    await service.start();
    await service.stop();

    await service.start();
    await settle();

    expect(emitted.map((id) => id.value), ['token-1', 'token-1']);
  });

  test('a token that arrives after stop is dropped', () async {
    final pending = Completer<String?>();
    final service = build(getToken: () => pending.future);

    final started = service.start();
    await service.stop();
    pending.complete('late');
    await started;
    await settle();

    expect(emitted, isEmpty);
    expect(service.current, isNull);
  });

  test('getToken failing does not throw and refreshes still work', () async {
    final service = build(getToken: () async => throw StateError('no GMS'));

    await service.start();
    refresh.add('later');
    await settle();

    expect(emitted.map((id) => id.value), ['later']);
  });

  test('a null token emits nothing', () async {
    final service = build(getToken: () async => null);

    await service.start();
    await settle();

    expect(emitted, isEmpty);
  });

  test('toString never reveals the registration value', () {
    const id = PushRegistrationId(
      value: 'super-secret-device-token',
      kind: PushRegistrationKind.token,
    );

    expect(id.toString(), isNot(contains('super-secret')));
    expect(id.toString(), contains('token'));
  });
}
