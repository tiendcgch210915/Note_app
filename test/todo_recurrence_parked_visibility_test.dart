import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todonote/data/api_client.dart';
import 'package:todonote/data/dashboard_repository.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/data/todos_repository.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/connectivity_sync.dart';
import 'package:todonote/utils/daily_score_calculator.dart';
import 'package:todonote/utils/todo_trigger_candidates.dart';

/// Một occurrence "đỗ" (`archived`) là sổ sách ẩn của series: phải biến mất khỏi
/// MỌI nguồn dữ liệu mà người dùng nhìn thấy, nhưng vẫn nằm trong Drift để lần
/// complete sau hồi sinh đúng row đó.
void main() {
  const userId = 'user-1';
  const seriesId = 'template';
  // Hôm sau ngày của root (2026-06-24): ngày của occurrence bị đỗ.
  const parkedDate = '2026-06-25';

  late AppDatabase db;
  late TodosRepository repository;
  late Future<http.Response> Function(http.Request) server;

  setUp(() {
    server = (_) async => http.Response('{}', 404);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TodosRepository.forTesting(
      db,
      userId: userId,
      client: ApiClient.forTesting(MockClient((request) => server(request))),
    );
  });

  tearDown(() async {
    ConnectivitySync.instance.cancelPending();
    await db.close();
  });

  Todo series({String? habitId}) => Todo(
    id: seriesId,
    title: 'Daily review',
    scheduledDate: DateTime(2026, 6, 24),
    recurrenceType: 'daily',
    habitId: habitId,
    createdAt: DateTime.utc(2026, 6, 24),
    updatedAt: DateTime.utc(2026, 6, 24),
  );

  /// Dựng đúng trạng thái thật: A đang mở (đã bỏ tick) + B đỗ ở ngày kế tiếp.
  ///
  /// Todo gắn habit không đi qua luồng complete được trong test vì
  /// `_applyHabitProjectionAfterComplete` chạm `HabitsRepository.instance`
  /// (singleton gắn DB thật), nên cặp A/B được ghi thẳng vào Drift.
  Future<({Todo reopened, String parkedId})> parkOne({String? habitId}) async {
    final root = series(habitId: habitId);
    await db.todosDao.upsertTodo(todoToCompanion(root, userId));
    if (habitId != null) {
      final parked = Todo(
        id: 'parked-direct',
        title: root.title,
        status: TodoStatus.archived,
        scheduledDate: DateTime(2026, 6, 25),
        habitId: habitId,
        recurrenceType: 'daily',
        recurrenceTemplateId: seriesId,
        createdAt: DateTime.utc(2026, 6, 24),
        updatedAt: DateTime.utc(2026, 6, 24),
      );
      await db.todosDao.upsertTodo(todoToCompanion(parked, userId));
      return (reopened: root, parkedId: parked.id);
    }
    final done = await repository.completeLocalFirst(root);
    final reopened = await repository.uncompleteLocalFirst(done.todo);
    final parkedId = done.nextRecurringTodo!.id;
    expect(
      (await db.todosDao.getTodoById(parkedId))!.status,
      TodoStatus.archived.backendValue,
    );
    return (reopened: reopened, parkedId: parkedId);
  }

  Map<String, dynamic> todoJson(
    String id, {
    required String status,
    required String date,
    String? habitId,
  }) => {
    'id': id,
    'title': 'Daily review',
    'status': status,
    'scheduled_date': date,
    'recurrence_type': 'daily',
    'recurrence_interval': 1,
    'recurrence_template_id': seriesId,
    'habit_id': habitId,
    'created_at': '2026-06-24T00:00:00.000Z',
    'updated_at': '2026-06-24T00:00:00.000Z',
  };

  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  group('local reads', () {
    test('listLocal hides the parked occurrence unless asked', () async {
      final parked = await parkOne();

      final visible = await repository.listLocal();
      expect(visible.map((todo) => todo.id), [seriesId]);

      final everything = await repository.listLocal(includeArchived: true);
      expect(everything.map((todo) => todo.id).toSet(), {
        seriesId,
        parked.parkedId,
      });
    });

    test('listByHabitLocal hides it (todos linked to a habit)', () async {
      await parkOne(habitId: 'habit-1');

      final linked = await repository.listByHabitLocal('habit-1');

      expect(linked.map((todo) => todo.id), [seriesId]);
    });

    test('the habit projection query ignores it', () async {
      final parked = await parkOne(habitId: 'habit-1');

      final live = await db.todosDao.getLiveTodosForHabitOnDate(
        'habit-1',
        parkedDate,
      );

      expect(live.map((row) => row.id), isNot(contains(parked.parkedId)));
    });

    test(
      'a todo triggered after another one is not "triggered" while parked',
      () async {
        final base = Todo(
          id: 'base',
          title: 'Base',
          createdAt: DateTime.utc(2026, 6, 24),
          updatedAt: DateTime.utc(2026, 6, 24),
        );
        Todo follower(String id, TodoStatus status) => Todo(
          id: id,
          title: id,
          status: status,
          triggerAfterTodoId: 'base',
          createdAt: DateTime.utc(2026, 6, 24, 1),
          updatedAt: DateTime.utc(2026, 6, 24, 1),
        );
        for (final todo in [
          base,
          follower('open-follower', TodoStatus.open),
          follower('parked-follower', TodoStatus.archived),
        ]) {
          await db.todosDao.upsertTodo(todoToCompanion(todo, userId));
        }

        final result = await repository.completeLocalFirst(base);

        expect(result.triggeredTodos.map((todo) => todo.id), ['open-follower']);
      },
    );

    test('trigger candidates skip it', () async {
      final parked = await parkOne();
      final all = await repository.listLocal(includeArchived: true);

      final candidates = filterTodoTriggerCandidates(all);

      expect(
        candidates.map((todo) => todo.id),
        isNot(contains(parked.parkedId)),
      );
    });

    test('the daily score does not count it', () async {
      final base = Todo(
        id: 'done-1',
        title: 'Done',
        status: TodoStatus.done,
        scheduledDate: DateTime(2026, 6, 25),
        completedAt: DateTime.utc(2026, 6, 25, 8),
        createdAt: DateTime.utc(2026, 6, 24),
        updatedAt: DateTime.utc(2026, 6, 25),
      );
      final parked = Todo(
        id: 'parked-1',
        title: 'Parked',
        status: TodoStatus.archived,
        scheduledDate: DateTime(2026, 6, 25),
        recurrenceType: 'daily',
        createdAt: DateTime.utc(2026, 6, 24),
        updatedAt: DateTime.utc(2026, 6, 25),
      );
      final date = DateTime(2026, 6, 25);

      final without = DailyScoreCalculator.calculate(
        todos: [base],
        date: date,
        habitsTotal: 0,
        habitsCompleted: 0,
      );
      final withParked = DailyScoreCalculator.calculate(
        todos: [base, parked],
        date: date,
        habitsTotal: 0,
        habitsCompleted: 0,
      );

      expect(withParked.score, without.score);
      expect(withParked.validCompletedTodos, without.validCompletedTodos);
    });

    test('the calendar day and its week strip do not count it', () async {
      final parked = await parkOne();
      final dashboard = DashboardRepository.forTesting(db);

      final parkedDay = await dashboard.localCalendarDayDetail(
        date: DateTime(2026, 6, 25),
      );
      expect(parkedDay.timedTodos, isEmpty);
      expect(parkedDay.untimedTodos, isEmpty);
      expect(parkedDay.totals.totalTodos, 0);
      final stripDay = parkedDay.week.days.singleWhere(
        (day) => day.dayOfMonth == 25,
      );
      expect(stripDay.totalTodos, 0);

      // Sanity: chính todo đang mở ở ngày của nó thì vẫn hiện.
      final reopenedDay = await dashboard.localCalendarDayDetail(
        date: DateTime(2026, 6, 24),
      );
      expect(
        [
          ...reopenedDay.timedTodos,
          ...reopenedDay.untimedTodos,
        ].map((todo) => todo.id),
        [seriesId],
      );
      expect(parked.parkedId, isNot(seriesId));
    });
  });

  group('REST reads (the backend does not hide parked rows)', () {
    test(
      'GET /todos drops parked rows from the result but still caches them',
      () async {
        server = (request) async => json({
          'items': [
            todoJson(seriesId, status: 'open', date: '2026-06-24'),
            todoJson('parked', status: 'archived', date: parkedDate),
          ],
          'nextCursor': null,
        });

        final result = await repository.list(limit: 100);

        expect(result.items.map((todo) => todo.id), [seriesId]);
        // Vẫn nằm trong Drift để lần complete sau hồi sinh đúng row này.
        expect(
          (await db.todosDao.getTodoById('parked'))!.status,
          TodoStatus.archived.backendValue,
        );
      },
    );

    test('GET /todos?habit_id= (habit detail) hides them too', () async {
      server = (request) async {
        expect(request.url.queryParameters['habit_id'], 'habit-1');
        return json({
          'items': [
            todoJson(
              seriesId,
              status: 'open',
              date: '2026-06-24',
              habitId: 'habit-1',
            ),
            todoJson(
              'parked',
              status: 'archived',
              date: parkedDate,
              habitId: 'habit-1',
            ),
          ],
          'nextCursor': null,
        });
      };

      final result = await repository.list(habitId: 'habit-1', limit: 100);

      expect(result.items.map((todo) => todo.id), [seriesId]);
    });

    test('asking for status=archived explicitly still returns them', () async {
      server = (request) async {
        expect(request.url.queryParameters['status'], 'archived');
        return json({
          'items': [todoJson('parked', status: 'archived', date: parkedDate)],
          'nextCursor': null,
        });
      };

      final result = await repository.list(status: TodoStatus.archived);

      expect(result.items.map((todo) => todo.id), ['parked']);
    });

    test(
      'GET /todos/day/:date hides them (Today list, legacy calendar)',
      () async {
        server = (request) async => json({
          'items': [
            {
              ...todoJson(seriesId, status: 'open', date: parkedDate),
              'has_subtasks': false,
            },
            {
              ...todoJson('parked', status: 'archived', date: parkedDate),
              'has_subtasks': false,
            },
          ],
        });

        final result = await repository.getDay(DateTime(2026, 6, 25));

        expect(result.map((item) => item.todo.id), [seriesId]);
        expect(
          (await db.todosDao.getTodoById('parked'))!.status,
          TodoStatus.archived.backendValue,
        );
      },
    );
  });
}
