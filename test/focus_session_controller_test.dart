import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/utils/focus_session_controller.dart';
import 'package:todonote/utils/todo_local_events.dart';

Todo _todo(
  String id, {
  String? title,
  TodoStatus status = TodoStatus.open,
  String? parentId,
}) {
  return Todo(
    id: id,
    title: title ?? 'Todo $id',
    status: status,
    parentId: parentId,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

TodoWithRelations _detail(Todo todo, [List<Todo> subtasks = const []]) {
  return TodoWithRelations(
    todo: todo,
    tags: const [],
    subtasks: subtasks,
    linkedNotes: const [],
  );
}

void main() {
  final controller = FocusSessionController.instance;
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 7, 9);
    controller.resetForTest();
    controller.clock = () => now;
    controller.localDetailLoader = (_) async => null;
  });

  tearDown(controller.resetForTest);

  group('countdown', () {
    testWidgets('derives remaining time from the wall clock', (tester) async {
      controller.start(_detail(_todo('a')), const Duration(seconds: 10));
      expect(controller.session.value!.remaining, const Duration(seconds: 10));

      // Một tick bị trễ (app ở nền) vẫn phải bù đủ thời gian đã trôi qua.
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.session.value!.remaining, const Duration(seconds: 7));

      now = now.add(const Duration(milliseconds: 2400));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.session.value!.remaining, const Duration(seconds: 5));

      controller.cancel();
    });

    testWidgets('clamps at zero and stops its timer', (tester) async {
      controller.start(_detail(_todo('a')), const Duration(seconds: 5));

      now = now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));

      expect(controller.session.value!.remaining, Duration.zero);
      expect(controller.session.value!.isOver, isTrue);
      // Không gọi cancel(): nếu timer vẫn chạy, testWidgets sẽ báo timer treo.
    });
  });

  group('lifecycle', () {
    testWidgets('start is refused while another todo is running', (
      tester,
    ) async {
      expect(
        controller.start(_detail(_todo('a')), const Duration(minutes: 5)),
        isTrue,
      );
      expect(
        controller.start(_detail(_todo('b')), const Duration(minutes: 25)),
        isFalse,
      );

      // Phiên đang chạy giữ nguyên, không bị thay thế hay reset.
      expect(controller.isActiveFor('a'), isTrue);
      expect(controller.isActiveFor('b'), isFalse);
      expect(controller.session.value!.total, const Duration(minutes: 5));

      controller.cancel();
    });

    testWidgets('a new todo can start once the previous one finished', (
      tester,
    ) async {
      controller.start(_detail(_todo('a')), const Duration(minutes: 5));
      controller.finish(completedAll: true);

      expect(
        controller.start(_detail(_todo('b')), const Duration(minutes: 25)),
        isTrue,
      );
      expect(controller.isActiveFor('b'), isTrue);

      controller.cancel();
    });

    testWidgets('finish returns the latest state and clears the session', (
      tester,
    ) async {
      final child = _todo('child', parentId: 'a');
      controller.start(
        _detail(_todo('a'), [child]),
        const Duration(minutes: 5),
      );
      controller.updateSubtasks([
        _todo('child', parentId: 'a', status: TodoStatus.done),
      ]);
      controller.addTriggered([_todo('next')]);
      controller.addTriggered([_todo('next')]);

      final result = controller.finish(completedAll: true);

      expect(controller.session.value, isNull);
      expect(result, isNotNull);
      expect(result!.completedAll, isTrue);
      expect(result.subtasks.single.isDone, isTrue);
      expect(result.triggeredTodos.map((t) => t.id), ['next']);
      expect(controller.finish(completedAll: false), isNull);
    });
  });

  group('staying consistent with local data', () {
    testWidgets('ends the session when the todo was deleted', (tester) async {
      controller.localDetailLoader = (_) async => null;
      controller.start(_detail(_todo('a')), const Duration(minutes: 5));

      TodoLocalEvents.instance.notifyChanged();
      await tester.pump();

      expect(controller.session.value, isNull);
    });

    testWidgets('ends a background session when the todo was completed', (
      tester,
    ) async {
      controller.localDetailLoader = (_) async =>
          _detail(_todo('a', status: TodoStatus.done));
      controller.start(_detail(_todo('a')), const Duration(minutes: 5));

      TodoLocalEvents.instance.notifyChanged();
      await tester.pump();

      expect(controller.session.value, isNull);
    });

    testWidgets('keeps the session while the focus screen is open', (
      tester,
    ) async {
      controller.localDetailLoader = (_) async =>
          _detail(_todo('a', status: TodoStatus.done));
      controller.start(_detail(_todo('a')), const Duration(minutes: 5));
      controller.focusScreenOpen.value = true;

      TodoLocalEvents.instance.notifyChanged();
      await tester.pump();

      expect(controller.session.value, isNotNull);
      expect(controller.session.value!.todo.isDone, isTrue);

      controller.cancel();
    });

    testWidgets('refreshes todo and subtasks but keeps the countdown', (
      tester,
    ) async {
      controller.start(_detail(_todo('a')), const Duration(seconds: 100));
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));

      controller.localDetailLoader = (_) async =>
          _detail(_todo('a', title: 'Renamed'), [_todo('c', parentId: 'a')]);
      TodoLocalEvents.instance.notifyChanged();
      await tester.pump();

      final session = controller.session.value!;
      expect(session.todo.title, 'Renamed');
      expect(session.subtasks.map((t) => t.id), ['c']);
      expect(session.remaining, const Duration(seconds: 70));

      controller.cancel();
    });

    testWidgets('drops an out-of-order refresh result', (tester) async {
      final older = Completer<TodoWithRelations?>();
      final newer = Completer<TodoWithRelations?>();
      final pending = [older, newer];
      var call = 0;
      controller.localDetailLoader = (_) => pending[call++].future;
      controller.start(_detail(_todo('a')), const Duration(minutes: 5));

      TodoLocalEvents.instance.notifyChanged();
      TodoLocalEvents.instance.notifyChanged();

      newer.complete(_detail(_todo('a', title: 'Newest')));
      await tester.pump();
      older.complete(_detail(_todo('a', title: 'Stale')));
      await tester.pump();

      expect(controller.session.value!.todo.title, 'Newest');

      controller.cancel();
    });

    testWidgets('ignores a refresh that lands after finish', (tester) async {
      final loading = Completer<TodoWithRelations?>();
      controller.localDetailLoader = (_) => loading.future;
      controller.start(_detail(_todo('a')), const Duration(minutes: 5));

      TodoLocalEvents.instance.notifyChanged();
      controller.finish(completedAll: true);
      loading.complete(_detail(_todo('a', title: 'Late')));
      await tester.pump();

      expect(controller.session.value, isNull);
    });
  });
}
