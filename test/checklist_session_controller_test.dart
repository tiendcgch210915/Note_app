import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/run.dart';
import 'package:todonote/models/run_item.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/utils/active_session_lock.dart';
import 'package:todonote/utils/checklist_local_events.dart';
import 'package:todonote/utils/checklist_session_controller.dart';
import 'package:todonote/utils/focus_session_controller.dart';

typedef _Local = ({Run run, List<RunItem> items});

Run _run(
  String id, {
  required DateTime startedAt,
  String templateId = 't1',
  String? name,
  RunStatus status = RunStatus.inProgress,
}) {
  return Run(
    id: id,
    templateId: templateId,
    name: name ?? 'Run $id',
    status: status,
    startedAt: startedAt,
  );
}

_Local _local(Run run, [List<RunItem> items = const []]) =>
    (run: run, items: items);

RunItem _item(String id, RunItemStatus status) {
  return RunItem(
    id: id,
    runId: 'r1',
    templateItemId: 'ti-$id',
    status: status,
    title: 'Bước $id',
    position: 1,
  );
}

TodoWithRelations _todoDetail(String id) {
  return TodoWithRelations(
    todo: Todo(
      id: id,
      title: 'Todo $id',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
    tags: const [],
    subtasks: const [],
    linkedNotes: const [],
  );
}

void main() {
  final controller = ChecklistSessionController.instance;
  final focus = FocusSessionController.instance;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 10, 9, 9);
    focus.resetForTest();
    controller.resetForTest();
    ActiveSessionLock.instance.resetForTest();
    controller.clock = () => now;
    controller.localRunLoader = (_) async => null;
  });

  tearDown(() {
    focus.resetForTest();
    controller.resetForTest();
  });

  group('count-up timer', () {
    testWidgets('starts from zero for a run that has just begun', (
      tester,
    ) async {
      expect(
        controller.start(_run('r1', startedAt: now), items: const []),
        isTrue,
      );

      expect(controller.session.value!.elapsed, Duration.zero);
      controller.cancel();
    });

    testWidgets('counts up one second at a time', (tester) async {
      controller.start(_run('r1', startedAt: now), items: const []);

      for (var second = 1; second <= 3; second++) {
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(controller.session.value!.elapsed, Duration(seconds: second));
      }
      controller.cancel();
    });

    testWidgets('continues from where the run really began', (tester) async {
      final startedAt = now.subtract(const Duration(minutes: 1, seconds: 30));
      controller.start(_run('r1', startedAt: startedAt), items: const []);

      expect(
        controller.session.value!.elapsed,
        const Duration(minutes: 1, seconds: 30),
      );
      controller.cancel();
    });

    testWidgets('catches up after a late tick (app was in the background)', (
      tester,
    ) async {
      controller.start(_run('r1', startedAt: now), items: const []);

      now = now.add(const Duration(seconds: 42));
      await tester.pump(const Duration(seconds: 1));

      expect(controller.session.value!.elapsed, const Duration(seconds: 42));
      controller.cancel();
    });

    testWidgets('never shows a negative time when the clock is behind', (
      tester,
    ) async {
      controller.start(
        _run('r1', startedAt: now.add(const Duration(minutes: 5))),
        items: const [],
      );
      await tester.pump(const Duration(seconds: 1));

      expect(controller.session.value!.elapsed, Duration.zero);
      controller.cancel();
    });

    testWidgets('ticks on the second boundary of the run, without drifting', (
      tester,
    ) async {
      // Run bắt đầu lúc xx:xx:00.600 → số giây phải nhảy vào mỗi .600.
      final startedAt = now.add(const Duration(milliseconds: 600));
      now = startedAt.add(const Duration(milliseconds: 100));
      controller.start(_run('r1', startedAt: startedAt), items: const []);
      expect(controller.session.value!.elapsed, Duration.zero);

      // Còn 900ms nữa mới tới giây thứ nhất: tick sớm hơn không được tính.
      await tester.pump(const Duration(milliseconds: 899));
      expect(controller.session.value!.elapsed, Duration.zero);

      now = startedAt.add(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.session.value!.elapsed, const Duration(seconds: 1));
      controller.cancel();
    });

    testWidgets('stops ticking after the session ends', (tester) async {
      controller.start(_run('r1', startedAt: now), items: const []);
      controller.finish(runId: 'r1');

      // Nếu timer còn sống, testWidgets sẽ báo timer chưa hủy khi kết thúc.
      await tester.pump(const Duration(seconds: 5));
      expect(controller.session.value, isNull);
    });
  });

  group('starting', () {
    testWidgets('exposes the run name, template and initial progress', (
      tester,
    ) async {
      controller.start(
        _run('r1', startedAt: now, templateId: 'tpl', name: 'Buổi sáng'),
        items: [
          _item('a', RunItemStatus.done),
          _item('b', RunItemStatus.skipped),
          _item('c', RunItemStatus.pending),
        ],
      );

      final session = controller.session.value!;
      expect(session.runId, 'r1');
      expect(session.templateId, 'tpl');
      expect(session.title, 'Buổi sáng');
      // Bước bỏ qua không tính là đã xong (giống màn hình run).
      expect(session.doneSteps, 1);
      expect(session.totalSteps, 3);
      controller.cancel();
    });

    testWidgets('only a run that is in progress can become a session', (
      tester,
    ) async {
      for (final status in [RunStatus.completed, RunStatus.abandoned]) {
        expect(
          controller.start(_run('r1', startedAt: now, status: status)),
          isFalse,
        );
      }
      expect(controller.session.value, isNull);
      expect(ActiveSessionLock.instance.holder, isNull);
    });

    testWidgets('starting the same run again keeps the running session', (
      tester,
    ) async {
      final run = _run('r1', startedAt: now);
      controller.start(run, items: [_item('a', RunItemStatus.done)]);
      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));

      expect(controller.start(run, items: const []), isTrue);

      expect(controller.session.value!.elapsed, const Duration(seconds: 10));
      expect(controller.session.value!.doneSteps, 1);
      controller.cancel();
    });
  });

  group('only one session at a time', () {
    testWidgets('a second checklist is refused', (tester) async {
      expect(
        controller.start(_run('r1', startedAt: now), items: const []),
        isTrue,
      );

      expect(
        controller.start(_run('r2', startedAt: now), items: const []),
        isFalse,
      );

      expect(controller.isActiveFor('r1'), isTrue);
      expect(controller.isActiveFor('r2'), isFalse);
      controller.cancel();
    });

    testWidgets('a todo cannot start while a checklist is running', (
      tester,
    ) async {
      controller.start(_run('r1', startedAt: now), items: const []);

      expect(
        focus.start(_todoDetail('a'), const Duration(minutes: 5)),
        isFalse,
      );

      expect(focus.session.value, isNull);
      expect(controller.isActiveFor('r1'), isTrue);
      controller.cancel();
    });

    testWidgets('a checklist cannot start while a todo is running', (
      tester,
    ) async {
      focus.start(_todoDetail('a'), const Duration(minutes: 5));

      expect(
        controller.start(_run('r1', startedAt: now), items: const []),
        isFalse,
      );

      expect(controller.session.value, isNull);
      expect(focus.isActiveFor('a'), isTrue);
      focus.cancel();
    });

    testWidgets('finishing the checklist frees the way for a todo', (
      tester,
    ) async {
      controller.start(_run('r1', startedAt: now), items: const []);
      controller.finish(runId: 'r1');

      expect(focus.start(_todoDetail('a'), const Duration(minutes: 5)), isTrue);
      focus.cancel();
    });

    testWidgets('finishing the todo frees the way for a checklist', (
      tester,
    ) async {
      focus.start(_todoDetail('a'), const Duration(minutes: 5));
      focus.finish(completedAll: false);

      expect(
        controller.start(_run('r1', startedAt: now), items: const []),
        isTrue,
      );
      controller.cancel();
    });

    testWidgets('cancelling releases the lock', (tester) async {
      controller.start(_run('r1', startedAt: now), items: const []);
      controller.cancel();

      expect(ActiveSessionLock.instance.holder, isNull);
      expect(
        controller.start(_run('r2', startedAt: now), items: const []),
        isTrue,
      );
      controller.cancel();
    });

    testWidgets('finish for another run does not end the current session', (
      tester,
    ) async {
      controller.start(_run('r1', startedAt: now), items: const []);

      expect(controller.finish(runId: 'someone-else'), isFalse);

      expect(controller.isActiveFor('r1'), isTrue);
      expect(controller.finish(runId: 'r1'), isTrue);
    });
  });

  group('staying consistent with local data', () {
    testWidgets('ends the session when the run was deleted', (tester) async {
      controller.start(_run('r1', startedAt: now), items: const []);

      ChecklistLocalEvents.instance.notifyChanged();
      await tester.pump();

      expect(controller.session.value, isNull);
      expect(ActiveSessionLock.instance.holder, isNull);
    });

    for (final status in [RunStatus.completed, RunStatus.abandoned]) {
      testWidgets('ends the session when the run became ${status.name}', (
        tester,
      ) async {
        controller.localRunLoader = (_) async =>
            _local(_run('r1', startedAt: now, status: status));
        controller.start(_run('r1', startedAt: now), items: const []);

        ChecklistLocalEvents.instance.notifyChanged();
        await tester.pump();

        expect(controller.session.value, isNull);
      });
    }

    testWidgets('refreshes name and progress but keeps the clock', (
      tester,
    ) async {
      controller.start(_run('r1', startedAt: now), items: const []);
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));

      controller.localRunLoader = (_) async => (
        run: _run('r1', startedAt: now, name: 'Đã đổi tên'),
        items: [
          _item('a', RunItemStatus.done),
          _item('b', RunItemStatus.done),
          _item('c', RunItemStatus.pending),
        ],
      );
      await controller.refreshFromLocal();

      final session = controller.session.value!;
      expect(session.title, 'Đã đổi tên');
      expect(session.doneSteps, 2);
      expect(session.totalSteps, 3);
      expect(session.elapsed, const Duration(seconds: 30));
      controller.cancel();
    });

    testWidgets('a failing read keeps the session as it was', (tester) async {
      controller.start(_run('r1', startedAt: now), items: const []);
      controller.localRunLoader = (_) => throw StateError('db closed');

      await controller.refreshFromLocal();

      expect(controller.isActiveFor('r1'), isTrue);
      controller.cancel();
    });

    testWidgets('drops an out-of-order refresh result', (tester) async {
      final older = Completer<_Local?>();
      final newer = Completer<_Local?>();
      final pending = [older, newer];
      var call = 0;
      controller.start(_run('r1', startedAt: now), items: const []);
      controller.localRunLoader = (_) => pending[call++].future;

      final first = controller.refreshFromLocal();
      final second = controller.refreshFromLocal();
      newer.complete(_local(_run('r1', startedAt: now, name: 'Mới nhất')));
      await second;
      older.complete(_local(_run('r1', startedAt: now, name: 'Cũ')));
      await first;

      expect(controller.session.value!.title, 'Mới nhất');
      controller.cancel();
    });

    testWidgets('ignores a refresh that lands after the session ended', (
      tester,
    ) async {
      final loading = Completer<_Local?>();
      controller.start(_run('r1', startedAt: now), items: const []);
      controller.localRunLoader = (_) => loading.future;

      final refresh = controller.refreshFromLocal();
      controller.finish(runId: 'r1');
      loading.complete(_local(_run('r1', startedAt: now)));
      await refresh;

      expect(controller.session.value, isNull);
    });

    testWidgets('loads progress itself when started without items', (
      tester,
    ) async {
      controller.localRunLoader = (_) async => (
        run: _run('r1', startedAt: now),
        items: [
          _item('a', RunItemStatus.done),
          _item('b', RunItemStatus.pending),
        ],
      );

      controller.start(_run('r1', startedAt: now));
      expect(controller.session.value!.totalSteps, isNull);
      await tester.pump();

      expect(controller.session.value!.doneSteps, 1);
      expect(controller.session.value!.totalSteps, 2);
      controller.cancel();
    });
  });

  group('open run screens', () {
    test('counts screens per run and reports when the last one closes', () {
      controller.screenOpened('r1');
      controller.screenOpened('r1');
      controller.screenOpened('r2');
      expect(controller.openRunScreens.value, {'r1', 'r2'});

      controller.screenClosed('r1');
      expect(controller.openRunScreens.value, {'r1', 'r2'});

      controller.screenClosed('r1');
      expect(controller.openRunScreens.value, {'r2'});

      controller.screenClosed('r2');
      controller.screenClosed('r2'); // Đóng thừa không gây lỗi.
      expect(controller.openRunScreens.value, isEmpty);
    });
  });
}
