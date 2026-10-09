import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/push/push_navigation.dart';
import 'package:todonote/push/push_target.dart';
import 'package:todonote/screens/shell/home_shell_controller.dart';

const _todo = PushTarget(type: 'todo', id: 't1');
const _note = PushTarget(type: 'note', id: 'n1');

void main() {
  late GlobalKey<NavigatorState> navigatorKey;
  late List<PushTarget> opened;
  var authenticated = true;

  PushNavigation build({bool Function(PushTarget)? opens}) => PushNavigation(
    navigatorKey: navigatorKey,
    isAuthenticated: () => authenticated,
    opener: (navigator, target) {
      opened.add(target);
      return opens?.call(target) ?? true;
    },
  );

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
  );

  setUp(() {
    navigatorKey = GlobalKey<NavigatorState>();
    opened = [];
    authenticated = true;
    HomeShellController.instance.setTab(0);
  });

  group('PushNavigation timing', () {
    testWidgets('a target received before the app is ready waits for it', (
      tester,
    ) async {
      await pumpApp(tester);
      final navigation = build();

      navigation.handle(_todo);

      expect(opened, isEmpty);
      expect(navigation.pending, _todo);

      navigation.markAppReady();
      await tester.pump();

      expect(opened, [_todo]);
      expect(navigation.pending, isNull);
    });

    testWidgets('only the most recent waiting target is opened', (
      tester,
    ) async {
      await pumpApp(tester);
      final navigation = build();

      navigation
        ..handle(_todo)
        ..handle(_note)
        ..markAppReady();
      await tester.pump();

      expect(opened, [_note]);
    });

    testWidgets('once ready, a target opens immediately', (tester) async {
      await pumpApp(tester);
      final navigation = build()..markAppReady();

      navigation.handle(_todo);

      expect(opened, [_todo]);
    });

    testWidgets('markAppReady twice does not replay anything', (tester) async {
      await pumpApp(tester);
      final navigation = build();
      navigation.handle(_todo);

      navigation
        ..markAppReady()
        ..markAppReady();
      await tester.pump();

      expect(opened, [_todo]);
    });

    testWidgets('appReady completes after markAppReady', (tester) async {
      await pumpApp(tester);
      final navigation = build();
      var ready = false;
      navigation.appReady.then((_) => ready = true);

      await tester.pump();
      expect(ready, isFalse);

      navigation.markAppReady();
      await tester.pump();
      expect(ready, isTrue);
    });
  });

  group('PushNavigation safety', () {
    testWidgets('ignores targets while logged out', (tester) async {
      await pumpApp(tester);
      authenticated = false;
      final navigation = build()..markAppReady();

      navigation.handle(_todo);

      expect(opened, isEmpty);
    });

    testWidgets('a cold-start target is dropped if nobody is logged in', (
      tester,
    ) async {
      await pumpApp(tester);
      authenticated = false;
      final navigation = build();

      navigation.handle(_todo);
      navigation.markAppReady();
      await tester.pump();

      expect(opened, isEmpty);
      expect(navigation.pending, isNull);
    });

    testWidgets('an unsupported target does not crash', (tester) async {
      await pumpApp(tester);
      final navigation = build(opens: (_) => false)..markAppReady();

      navigation.handle(const PushTarget(type: 'mystery'));

      expect(opened, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('does nothing without a navigator', (tester) async {
      // navigatorKey chưa gắn vào widget nào.
      final navigation = build()..markAppReady();

      navigation.handle(_todo);

      expect(opened, isEmpty);
    });
  });

  group('openPushTarget', () {
    testWidgets('"example" goes back to the Today tab', (tester) async {
      await pumpApp(tester);
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('deep')),
      );
      await tester.pumpAndSettle();
      HomeShellController.instance.setTab(3);
      expect(find.text('deep'), findsOneWidget);

      final opened = openPushTarget(
        navigatorKey.currentState!,
        const PushTarget(type: 'example'),
      );
      await tester.pumpAndSettle();

      expect(opened, isTrue);
      expect(find.text('deep'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(HomeShellController.instance.currentIndex.value, 0);
    });

    testWidgets('types that need an id are rejected without one', (
      tester,
    ) async {
      await pumpApp(tester);
      final navigator = navigatorKey.currentState!;

      for (final type in const [
        'todo',
        'note',
        'habit',
        'checklist_run',
        'checklist_template',
      ]) {
        expect(
          openPushTarget(navigator, PushTarget(type: type)),
          isFalse,
          reason: type,
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('unknown types are ignored', (tester) async {
      await pumpApp(tester);

      final opened = openPushTarget(
        navigatorKey.currentState!,
        const PushTarget(type: 'mystery', id: 'x'),
      );

      expect(opened, isFalse);
    });
  });
}
