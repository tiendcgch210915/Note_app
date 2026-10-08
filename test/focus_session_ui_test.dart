import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/screens/shell/home_shell_controller.dart';
import 'package:todonote/screens/todos/todo_detail_screen.dart';
import 'package:todonote/utils/app_navigator.dart';
import 'package:todonote/utils/focus_session_controller.dart';
import 'package:todonote/widgets/focus_session_banner.dart';
import 'package:todonote/widgets/todo_detail_route_tracker.dart';

const _bannerKey = ValueKey('focus-session-banner');

Todo _todo(String id) => Todo(
  id: id,
  title: 'Todo $id',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

TodoWithRelations _detail(Todo todo) => TodoWithRelations(
  todo: todo,
  tags: const [],
  subtasks: const [],
  linkedNotes: const [],
);

Widget _app() {
  return MaterialApp(
    navigatorKey: rootNavigatorKey,
    builder: (context, child) => FocusSessionBannerHost(child: child!),
    home: Scaffold(
      body: const Center(child: Text('root')),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'A'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'B'),
        ],
      ),
    ),
  );
}

void main() {
  final controller = FocusSessionController.instance;

  setUp(() {
    controller.resetForTest();
    controller.clock = () => DateTime(2026, 10, 7, 9);
    controller.localDetailLoader = (_) async => null;
    HomeShellController.instance.setTab(0);
  });

  tearDown(() {
    controller.resetForTest();
    HomeShellController.instance.setTab(0);
  });

  void startSession(String id, {Duration? duration}) {
    controller.start(
      _detail(_todo(id)),
      duration ?? const Duration(minutes: 25),
    );
  }

  group('banner', () {
    testWidgets('is absent without a session', (tester) async {
      await tester.pumpWidget(_app());
      expect(find.byKey(_bannerKey), findsNothing);
    });

    testWidgets('shows title and time and sits below the bottom nav', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      startSession('a');
      await tester.pump();

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.text('Todo a'), findsOneWidget);
      expect(find.text('25:00'), findsOneWidget);

      final navBottom = tester.getBottomLeft(find.byType(BottomNavigationBar));
      final bannerTop = tester.getTopLeft(find.byKey(_bannerKey));
      expect(bannerTop.dy, greaterThanOrEqualTo(navBottom.dy));

      controller.cancel();
      await tester.pump();
      expect(find.byKey(_bannerKey), findsNothing);
    });

    testWidgets('says "Hết giờ" once the countdown is over', (tester) async {
      await tester.pumpWidget(_app());
      startSession('a', duration: Duration.zero);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Hết giờ'), findsOneWidget);
      controller.cancel();
    });

    testWidgets('hides while the focus screen is open', (tester) async {
      await tester.pumpWidget(_app());
      startSession('a');
      await tester.pump();

      controller.focusScreenOpen.value = true;
      await tester.pump();
      expect(find.byKey(_bannerKey), findsNothing);

      controller.focusScreenOpen.value = false;
      await tester.pump();
      expect(find.byKey(_bannerKey), findsOneWidget);
      controller.cancel();
    });

    testWidgets('hides while the keyboard is open', (tester) async {
      await tester.pumpWidget(_app());
      startSession('a');
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(find.byKey(_bannerKey), findsNothing);

      tester.view.resetViewInsets();
      await tester.pump();
      expect(find.byKey(_bannerKey), findsOneWidget);
      controller.cancel();
    });

    testWidgets('stop button asks first, then ends the session', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      startSession('a');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('focus-session-banner-stop')));
      await tester.pumpAndSettle();
      expect(find.text('Kết thúc phiên tập trung?'), findsOneWidget);

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(controller.session.value, isNotNull);

      await tester.tap(find.byKey(const ValueKey('focus-session-banner-stop')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Kết thúc'));
      await tester.pumpAndSettle();

      expect(controller.session.value, isNull);
      expect(find.byKey(_bannerKey), findsNothing);
    });

    testWidgets('tapping it reopens the focus screen without a duplicate', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      startSession('a');
      await tester.pump();

      await tester.tap(find.text('Todo a'));
      await tester.pumpAndSettle();

      expect(find.byType(TodoFocusScreen), findsOneWidget);
      expect(find.byKey(_bannerKey), findsNothing);

      unawaited(resumeFocusSession());
      await tester.pumpAndSettle();
      expect(find.byType(TodoFocusScreen), findsOneWidget);

      controller.cancel();
      await tester.pumpAndSettle();
    });
  });

  group('focus screen navigation', () {
    Future<void> openFocus(
      WidgetTester tester, {
      Widget Function(DateTime)? cal,
    }) async {
      await tester.pumpWidget(_app());
      startSession('a');
      controller.focusScreenOpen.value = true;
      unawaited(
        rootNavigatorKey.currentState!.push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => TodoFocusScreen(todayCalendarBuilder: cal),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TodoFocusScreen), findsOneWidget);
    }

    testWidgets('home button returns to root and keeps the timer running', (
      tester,
    ) async {
      await openFocus(tester);
      HomeShellController.instance.setTab(3);

      await tester.tap(find.byKey(const ValueKey('focus-home')));
      controller.focusScreenOpen.value = false;
      await tester.pumpAndSettle();

      expect(find.byType(TodoFocusScreen), findsNothing);
      expect(find.text('root'), findsOneWidget);
      expect(HomeShellController.instance.currentIndex.value, 0);
      expect(controller.isActiveFor('a'), isTrue);
      expect(find.byKey(_bannerKey), findsOneWidget);

      controller.cancel();
    });

    testWidgets('calendar button jumps to the Lịch tab and today\'s detail', (
      tester,
    ) async {
      DateTime? requested;
      await openFocus(
        tester,
        cal: (today) {
          requested = today;
          return Scaffold(body: Text('calendar-detail ${today.day}'));
        },
      );

      await tester.tap(find.byKey(const ValueKey('focus-calendar')));
      controller.focusScreenOpen.value = false;
      await tester.pumpAndSettle();

      final today = DateTime.now();
      expect(requested, DateTime(today.year, today.month, today.day));
      expect(find.text('calendar-detail ${today.day}'), findsOneWidget);
      expect(find.byType(TodoFocusScreen), findsNothing);
      expect(HomeShellController.instance.currentIndex.value, 4);
      expect(controller.isActiveFor('a'), isTrue);

      controller.cancel();
    });

    group('X asks before leaving', () {
      const closeKey = ValueKey('focus-close');
      const backKey = ValueKey('focus-leave-back');
      const cancelKey = ValueKey('focus-leave-cancel');

      // Mở màn Focus qua `openTodoFocusScreen` và ghi lại kết quả của nó.
      Future<({List<FocusSessionResult?> results})> openTracked(
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(_app());
        startSession('a');
        final results = <FocusSessionResult?>[];
        unawaited(
          openTodoFocusScreen(rootNavigatorKey.currentState!).then(results.add),
        );
        await tester.pumpAndSettle();
        return (results: results);
      }

      testWidgets('shows both choices and changes nothing yet', (tester) async {
        final opened = await openTracked(tester);

        await tester.tap(find.byKey(closeKey));
        await tester.pumpAndSettle();

        expect(find.text('Thoát bấm giờ?'), findsOneWidget);
        expect(find.byKey(backKey), findsOneWidget);
        expect(find.byKey(cancelKey), findsOneWidget);
        expect(find.byType(TodoFocusScreen), findsOneWidget);
        expect(controller.isActiveFor('a'), isTrue);
        expect(opened.results, isEmpty);

        controller.cancel();
        await tester.pumpAndSettle();
      });

      testWidgets('tapping outside the dialog stays on the focus screen', (
        tester,
      ) async {
        final opened = await openTracked(tester);

        await tester.tap(find.byKey(closeKey));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        expect(find.text('Thoát bấm giờ?'), findsNothing);
        expect(find.byType(TodoFocusScreen), findsOneWidget);
        expect(controller.isActiveFor('a'), isTrue);
        expect(opened.results, isEmpty);

        // Bấm X lần nữa vẫn mở lại được hộp thoại.
        await tester.tap(find.byKey(closeKey));
        await tester.pumpAndSettle();
        expect(find.text('Thoát bấm giờ?'), findsOneWidget);

        controller.cancel();
        await tester.pumpAndSettle();
      });

      testWidgets('"Trở lại" goes home and keeps the timer running', (
        tester,
      ) async {
        final opened = await openTracked(tester);
        HomeShellController.instance.setTab(3);

        await tester.tap(find.byKey(closeKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(backKey));
        await tester.pumpAndSettle();

        expect(find.byType(TodoFocusScreen), findsNothing);
        expect(find.text('Thoát bấm giờ?'), findsNothing);
        expect(find.text('root'), findsOneWidget);
        expect(HomeShellController.instance.currentIndex.value, 0);
        expect(controller.isActiveFor('a'), isTrue);
        expect(controller.focusScreenOpen.value, isFalse);
        expect(find.byKey(_bannerKey), findsOneWidget);
        expect(opened.results, [isNull]);

        controller.cancel();
      });

      testWidgets('"Hủy bấm giờ" stops the session and reports a cancel', (
        tester,
      ) async {
        final opened = await openTracked(tester);

        await tester.tap(find.byKey(closeKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(cancelKey));
        await tester.pumpAndSettle();

        expect(find.byType(TodoFocusScreen), findsNothing);
        expect(find.text('Thoát bấm giờ?'), findsNothing);
        expect(controller.session.value, isNull);
        expect(controller.focusScreenOpen.value, isFalse);
        expect(find.byKey(_bannerKey), findsNothing);
        expect(opened.results, hasLength(1));
        expect(opened.results.single!.completedAll, isFalse);
        expect(opened.results.single!.todo.id, 'a');
      });

      testWidgets('closes the dialog and screen if the session is cancelled', (
        tester,
      ) async {
        await openTracked(tester);

        await tester.tap(find.byKey(closeKey));
        await tester.pumpAndSettle();
        controller.cancel();
        await tester.pumpAndSettle();

        expect(find.text('Thoát bấm giờ?'), findsNothing);
        expect(find.byType(TodoFocusScreen), findsNothing);
        expect(find.text('root'), findsOneWidget);
      });
    });

    group('cancelling after resuming from the banner', () {
      Future<void> resumeThenCancel(
        WidgetTester tester, {
        bool detailBeneath = false,
      }) async {
        await tester.pumpWidget(_app());
        startSession('a');
        if (detailBeneath) {
          unawaited(
            rootNavigatorKey.currentState!.push(
              MaterialPageRoute(
                builder: (_) => const TodoDetailRouteTracker(
                  todoId: 'a',
                  child: Scaffold(body: Text('real-detail-a')),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        unawaited(
          resumeFocusSession(
            detailBuilder: (id) => Scaffold(body: Text('opened-detail-$id')),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('focus-close')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('focus-leave-cancel')));
        await tester.pumpAndSettle();
      }

      testWidgets('opens the todo detail page when none is underneath', (
        tester,
      ) async {
        await resumeThenCancel(tester);

        expect(controller.session.value, isNull);
        expect(find.byType(TodoFocusScreen), findsNothing);
        expect(find.text('opened-detail-a'), findsOneWidget);
      });

      testWidgets('reuses the detail page that is already underneath', (
        tester,
      ) async {
        await resumeThenCancel(tester, detailBeneath: true);

        expect(controller.session.value, isNull);
        expect(find.text('real-detail-a'), findsOneWidget);
        expect(find.text('opened-detail-a'), findsNothing);
      });

      testWidgets('"Trở lại" does not open any detail page', (tester) async {
        await tester.pumpWidget(_app());
        startSession('a');
        unawaited(
          resumeFocusSession(
            detailBuilder: (id) => Scaffold(body: Text('opened-detail-$id')),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('focus-close')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('focus-leave-back')));
        await tester.pumpAndSettle();

        expect(find.text('opened-detail-a'), findsNothing);
        expect(find.text('root'), findsOneWidget);
        expect(controller.isActiveFor('a'), isTrue);

        controller.cancel();
      });
    });

    group('TodoDetailRouteTracker', () {
      testWidgets('reports only the detail page that is on top', (
        tester,
      ) async {
        await tester.pumpWidget(_app());
        final navigator = rootNavigatorKey.currentState!;
        expect(TodoDetailRouteTracker.currentTodoId, isNull);

        unawaited(
          navigator.push(
            MaterialPageRoute(
              builder: (_) => const TodoDetailRouteTracker(
                todoId: 'a',
                child: Scaffold(body: Text('detail-a')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(TodoDetailRouteTracker.currentTodoId, 'a');

        unawaited(
          navigator.push(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('other')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(TodoDetailRouteTracker.currentTodoId, isNull);

        navigator.pop();
        await tester.pumpAndSettle();
        expect(TodoDetailRouteTracker.currentTodoId, 'a');

        navigator.pop();
        await tester.pumpAndSettle();
        expect(TodoDetailRouteTracker.currentTodoId, isNull);
      });
    });

    testWidgets('system back minimises instead of ending the session', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      startSession('a');
      FocusSessionResult? result = FocusSessionResult(
        todo: _todo('sentinel'),
        subtasks: const [],
        triggeredTodos: const [],
        completedAll: true,
      );
      unawaited(
        openTodoFocusScreen(rootNavigatorKey.currentState!).then((v) {
          result = v;
        }),
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(controller.isActiveFor('a'), isTrue);
      expect(controller.focusScreenOpen.value, isFalse);
      expect(find.byKey(_bannerKey), findsOneWidget);

      controller.cancel();
    });

    testWidgets('closes itself when the session is cancelled elsewhere', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      startSession('a');
      unawaited(openTodoFocusScreen(rootNavigatorKey.currentState!));
      await tester.pumpAndSettle();
      expect(find.byType(TodoFocusScreen), findsOneWidget);

      controller.cancel();
      await tester.pumpAndSettle();

      expect(find.byType(TodoFocusScreen), findsNothing);
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('does not open without a running session', (tester) async {
      await tester.pumpWidget(_app());
      final result = await openTodoFocusScreen(rootNavigatorKey.currentState!);
      await tester.pump();

      expect(result, isNull);
      expect(find.byType(TodoFocusScreen), findsNothing);
      expect(controller.focusScreenOpen.value, isFalse);
    });
  });
}
