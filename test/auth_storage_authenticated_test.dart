import 'dart:ui' show VoidCallback;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/auth_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = AuthStorage.instance;
  late List<bool> changes;
  late VoidCallback stopListening;

  setUp(() {
    changes = [];
    void listener() => changes.add(storage.authenticated.value);
    storage.authenticated.addListener(listener);
    stopListening = () => storage.authenticated.removeListener(listener);
  });

  tearDown(() async {
    stopListening();
    FlutterSecureStorage.setMockInitialValues({});
    await storage.init();
  });

  test('is true after init when a token is stored', () async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'jwt'});
    await storage.init();

    expect(storage.authenticated.value, isTrue);
  });

  test('is false after init when nothing is stored', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.init();

    expect(storage.authenticated.value, isFalse);
  });

  test('follows login → logout (including a 401 clear)', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.init();
    changes.clear();

    await storage.saveToken('jwt');
    await storage.clear();

    expect(changes, [true, false]);
  });

  test('an empty token does not count as authenticated', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.init();

    await storage.saveToken('');

    expect(storage.authenticated.value, isFalse);
  });

  test('re-saving the same token does not notify again', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.init();
    await storage.saveToken('jwt');
    changes.clear();

    await storage.saveToken('jwt-2');

    expect(changes, isEmpty);
  });
}
