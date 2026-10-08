import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/dashboard.dart';
import 'package:todonote/widgets/calendar_day_timeline.dart';

void main() {
  testWidgets('timeline compresses empty hours between timed todos', (
    tester,
  ) async {
    final detail = _detail(
      currentVisible: true,
      timedTodos: const [
        CalendarDayTodo(
          id: '18h',
          title: 'Đi tập GYM',
          status: 'open',
          position: 2,
          scheduledDate: null,
          time: '18:00',
          minutesSinceMidnight: 1080,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
        CalendarDayTodo(
          id: '9h',
          title: 'Học tiếng Anh',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '09:00',
          minutesSinceMidnight: 540,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail);

    final nineTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-9h')))
        .dy;
    final eighteenTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-18h')))
        .dy;

    expect(eighteenTop - nineTop, closeTo(510, 1));
    expect(_richTextContaining('[09:00]'), findsOneWidget);
    expect(_richTextContaining('[18:00]'), findsOneWidget);
  });

  testWidgets('half-hour mark shows only when both halves have todos', (
    tester,
  ) async {
    CalendarDayTodo todo(String id, int minute) {
      final hour = (minute ~/ 60).toString().padLeft(2, '0');
      final min = (minute % 60).toString().padLeft(2, '0');
      return CalendarDayTodo(
        id: id,
        title: 'Todo $id',
        status: 'open',
        position: minute,
        scheduledDate: null,
        time: '$hour:$min',
        minutesSinceMidnight: minute,
        isFrog: false,
        isImportant: false,
        isUrgent: false,
        hasSubtasks: false,
      );
    }

    final detail = _detail(
      currentVisible: false,
      timedTodos: [
        todo('4h15', 255),
        todo('4h45', 285),
        todo('6h30', 390),
        todo('8h10', 490),
        todo('8h20', 500),
        todo('10h40', 640),
        todo('10h50', 650),
        todo('10h55', 655),
      ],
    );

    await _pumpTimeline(tester, detail);

    expect(
      find.byKey(const ValueKey('calendar-half-hour-label-270')),
      findsOneWidget,
    );
    for (final minute in [330, 390, 510, 630]) {
      expect(
        find.byKey(ValueKey('calendar-half-hour-label-$minute')),
        findsNothing,
        reason: 'no :30 mark expected at minute $minute',
      );
    }

    final fourTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-240')))
        .dy;
    final fourThirtyTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-half-hour-label-270')))
        .dy;
    final todo415Top = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-4h15')))
        .dy;
    final todo445Top = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-4h45')))
        .dy;

    expect(todo415Top, greaterThan(fourTop));
    expect(todo415Top, lessThan(fourThirtyTop));
    expect(todo445Top, greaterThan(fourThirtyTop));
  });

  testWidgets('same-hour todos expand the hour instead of spilling into next', (
    tester,
  ) async {
    final detail = _detail(
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: '9a',
          title: 'Việc đầu tiên',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '09:00',
          minutesSinceMidnight: 540,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
        CalendarDayTodo(
          id: '9b',
          title: 'Việc thứ hai',
          status: 'open',
          position: 2,
          scheduledDate: null,
          time: '09:00',
          minutesSinceMidnight: 540,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail);

    final firstBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-9a')))
        .dy;
    final secondTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-9b')))
        .dy;
    final secondBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-9b')))
        .dy;
    final tenTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-600')))
        .dy;

    expect(secondTop, greaterThanOrEqualTo(firstBottom));
    expect(secondBottom, lessThanOrEqualTo(tenTop));
  });

  testWidgets('empty half inside an occupied hour stays compact', (
    tester,
  ) async {
    final detail = _detail(
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: '15h30',
          title: 'Việc lúc 15:30',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '15:30',
          minutesSinceMidnight: 930,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
        CalendarDayTodo(
          id: '15h45',
          title: 'Việc lúc 15:45',
          status: 'open',
          position: 2,
          scheduledDate: null,
          time: '15:45',
          minutesSinceMidnight: 945,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail);

    expect(
      find.byKey(const ValueKey('calendar-half-hour-label-930')),
      findsNothing,
    );

    final fifteenTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-900')))
        .dy;
    final sixteenTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-960')))
        .dy;
    final firstTodoTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-15h30')))
        .dy;
    final firstTodoBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-15h30')))
        .dy;
    final secondTodoTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-15h45')))
        .dy;
    final secondTodoBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-15h45')))
        .dy;

    expect(firstTodoTop - fifteenTop, lessThan(40));
    expect(sixteenTop - firstTodoTop, greaterThan(120));
    expect(secondTodoTop, greaterThanOrEqualTo(firstTodoBottom));
    expect(secondTodoBottom, lessThanOrEqualTo(sixteenTop));
  });

  testWidgets('close todos inside one hour do not overlap visually', (
    tester,
  ) async {
    final detail = _detail(
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: '8h05',
          title: 'Việc lúc 8:05',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '08:05',
          minutesSinceMidnight: 485,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
        CalendarDayTodo(
          id: '8h10',
          title: 'Việc lúc 8:10',
          status: 'open',
          position: 2,
          scheduledDate: null,
          time: '08:10',
          minutesSinceMidnight: 490,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail);

    final firstBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-8h05')))
        .dy;
    final secondTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-8h10')))
        .dy;
    final secondBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-8h10')))
        .dy;
    final nineTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-540')))
        .dy;

    expect(secondTop, greaterThanOrEqualTo(firstBottom));
    expect(secondBottom, lessThanOrEqualTo(nineTop));
  });

  testWidgets('estimated timed todo spans through compact continuation hours', (
    tester,
  ) async {
    final detail = _detail(
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: '3h',
          title: 'Deep work',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '03:00',
          minutesSinceMidnight: 180,
          estimatedMinutes: 120,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
        CalendarDayTodo(
          id: '6h',
          title: 'Làm bản nháp',
          status: 'open',
          position: 2,
          scheduledDate: null,
          time: '06:00',
          minutesSinceMidnight: 360,
          estimatedMinutes: 90,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail);

    final threeTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-180')))
        .dy;
    final fiveTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-300')))
        .dy;
    final threeTodoTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-3h')))
        .dy;
    final threeTodoBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-3h')))
        .dy;

    final sevenTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-420')))
        .dy;
    final eightTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-480')))
        .dy;
    final sixTodoBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-6h')))
        .dy;

    expect(threeTodoTop, closeTo(threeTop, 1));
    expect(threeTodoBottom, closeTo(fiveTop, 1));
    expect(
      find.byKey(const ValueKey('calendar-half-hour-label-450')),
      findsNothing,
    );
    expect(sixTodoBottom, closeTo((sevenTop + eightTop) / 2, 1));
  });

  testWidgets('single todo with a long duration shows no half-hour marks', (
    tester,
  ) async {
    final detail = _detail(
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: '19h',
          title: 'Phiên tập trung dài',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '19:00',
          minutesSinceMidnight: 1140,
          estimatedMinutes: 150,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail);

    expect(
      find.byKey(const ValueKey('calendar-half-hour-label-1170')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('calendar-half-hour-label-1230')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('calendar-half-hour-label-1290')),
      findsNothing,
    );

    final twentyOneTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-1260')))
        .dy;
    final twentyTwoTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-1320')))
        .dy;
    final todoBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-19h')))
        .dy;

    expect(todoBottom, closeTo((twentyOneTop + twentyTwoTop) / 2, 1));
  });

  testWidgets('done timed todos render muted and compact', (tester) async {
    final detail = _detail(
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: 'done',
          title: 'Đã gửi báo cáo',
          status: 'done',
          position: 1,
          scheduledDate: null,
          time: '09:00',
          minutesSinceMidnight: 540,
          estimatedMinutes: 90,
          isFrog: true,
          isImportant: true,
          isUrgent: true,
          hasSubtasks: true,
        ),
        CalendarDayTodo(
          id: 'open',
          title: 'Việc còn lại',
          status: 'open',
          position: 2,
          scheduledDate: null,
          time: '10:00',
          minutesSinceMidnight: 600,
          estimatedMinutes: 90,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail);

    final doneSize = tester.getSize(
      find.byKey(const ValueKey('calendar-todo-done')),
    );
    final openSize = tester.getSize(
      find.byKey(const ValueKey('calendar-todo-open')),
    );

    expect(doneSize.height, lessThan(openSize.height));
    expect(doneSize.height, closeTo(34, 1));
    expect(_richTextContaining('[09:00] Đã gửi báo cáo'), findsOneWidget);
    expect(find.text('90 phút'), findsOneWidget);
  });

  testWidgets('completed-only occupied half-hour shrinks to compact cards', (
    tester,
  ) async {
    final detail = _detail(
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: 'done-1530',
          title: 'Đã xử lý email',
          status: 'done',
          position: 1,
          scheduledDate: null,
          time: '15:30',
          minutesSinceMidnight: 930,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
        CalendarDayTodo(
          id: 'done-1545',
          title: 'Đã ghi log',
          status: 'done',
          position: 2,
          scheduledDate: null,
          time: '15:45',
          minutesSinceMidnight: 945,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail);

    final firstTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-done-1530')))
        .dy;
    final sixteenTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-960')))
        .dy;
    final firstBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-done-1530')))
        .dy;
    final secondTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-todo-done-1545')))
        .dy;
    final secondBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-done-1545')))
        .dy;

    expect(sixteenTop - firstTop, lessThan(96));
    expect(secondTop, greaterThanOrEqualTo(firstBottom));
    expect(secondBottom, lessThanOrEqualTo(sixteenTop));
  });

  testWidgets('open todo exposes a larger completion target', (tester) async {
    final completed = <String>[];
    final opened = <String>[];
    final detail = _detail(
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: 'open',
          title: 'Việc còn lại',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '01:00',
          minutesSinceMidnight: 60,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(
      tester,
      detail,
      onTodoTap: (todo) => opened.add(todo.id),
      onTodoComplete: (todo) => completed.add(todo.id),
    );

    final target = find.byKey(const ValueKey('calendar-complete-open'));
    expect(target, findsOneWidget);
    expect(tester.getSize(target).width, greaterThanOrEqualTo(34));

    await tester.tap(target);
    await tester.pump();

    expect(completed, ['open']);
    expect(opened, isEmpty);
  });

  testWidgets('daily log todo is locked and cannot be completed directly', (
    tester,
  ) async {
    final completed = <String>[];
    final opened = <String>[];
    final detail = _detail(
      date: DateTime(2026, 6, 20),
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: 'log-todo',
          source: 'daily_log',
          isDailyLog: true,
          logId: 'log-1',
          todoId: 'todo-live-id',
          lockedCompleted: false,
          title: 'Hoàn thành muộn',
          status: 'done',
          position: 1,
          scheduledDate: null,
          time: '09:00',
          minutesSinceMidnight: 540,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(
      tester,
      detail,
      onTodoTap: (todo) => opened.add(todo.todoId),
      onTodoComplete: (todo) => completed.add(todo.id),
    );

    expect(find.text('Đã chốt: chưa xong'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-complete-log-todo')));
    await tester.pump();

    expect(completed, isEmpty);
    expect(opened, ['todo-live-id']);
  });

  testWidgets('timeline hides time labels only when closer than ten minutes', (
    tester,
  ) async {
    final detail = _detail(
      currentVisible: true,
      timedTodos: const [
        CalendarDayTodo(
          id: '18h',
          title: 'Todo lúc 18h',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '18:00',
          minutesSinceMidnight: 1080,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail, now: DateTime(2026, 6, 26, 3, 50));

    expect(
      find.byKey(const ValueKey('calendar-hour-label-240')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-current-time-line')),
      findsOneWidget,
    );
    expect(find.text('03:50'), findsOneWidget);

    await _pumpTimeline(tester, detail, now: DateTime(2026, 6, 26, 3, 51));

    expect(find.byKey(const ValueKey('calendar-hour-label-240')), findsNothing);

    await _pumpTimeline(tester, detail, now: DateTime(2026, 6, 26, 4, 10));

    expect(
      find.byKey(const ValueKey('calendar-hour-label-240')),
      findsOneWidget,
    );
  });

  testWidgets('timeline applies ten-minute hiding to half-hour marks', (
    tester,
  ) async {
    final detail = _detail(
      currentVisible: true,
      timedTodos: const [
        CalendarDayTodo(
          id: '4h15',
          title: 'Todo lúc 4:15',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '04:15',
          minutesSinceMidnight: 255,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
        CalendarDayTodo(
          id: '4h45',
          title: 'Todo lúc 4:45',
          status: 'open',
          position: 2,
          scheduledDate: null,
          time: '04:45',
          minutesSinceMidnight: 285,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail, now: DateTime(2026, 6, 26, 4, 21));

    expect(
      find.byKey(const ValueKey('calendar-half-hour-label-270')),
      findsNothing,
    );

    await _pumpTimeline(tester, detail, now: DateTime(2026, 6, 26, 4, 40));

    expect(
      find.byKey(const ValueKey('calendar-half-hour-label-270')),
      findsOneWidget,
    );
  });

  testWidgets('current time is not nudged by a half-hour mark that is hidden', (
    tester,
  ) async {
    CalendarDayTodo todo(String id, int minute) {
      final hour = (minute ~/ 60).toString().padLeft(2, '0');
      final min = (minute % 60).toString().padLeft(2, '0');
      return CalendarDayTodo(
        id: id,
        title: 'Todo $id',
        status: 'open',
        position: minute,
        scheduledDate: null,
        time: '$hour:$min',
        minutesSinceMidnight: minute,
        isFrog: false,
        isImportant: false,
        isUrgent: false,
        hasSubtasks: false,
      );
    }

    final now = DateTime(2026, 6, 26, 4, 29);

    await _pumpTimeline(
      tester,
      _detail(currentVisible: true, timedTodos: [todo('a', 255)]),
      now: now,
    );
    final fourTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-mark-240')))
        .dy;
    final withoutMark =
        tester
            .getTopLeft(
              find.byKey(const ValueKey('calendar-current-time-line')),
            )
            .dy -
        fourTop;

    await _pumpTimeline(
      tester,
      _detail(
        currentVisible: true,
        timedTodos: [todo('a', 255), todo('b', 285)],
      ),
      now: now,
    );
    final withMark =
        tester
            .getTopLeft(
              find.byKey(const ValueKey('calendar-current-time-line')),
            )
            .dy -
        tester
            .getTopLeft(find.byKey(const ValueKey('calendar-hour-mark-240')))
            .dy;

    expect(
      find.byKey(const ValueKey('calendar-half-hour-label-270')),
      findsNothing,
    );
    expect(withoutMark, greaterThan(withMark));
  });

  testWidgets('current time stays before hidden future hour mark', (
    tester,
  ) async {
    final detail = _detail(
      currentVisible: true,
      timedTodos: const [
        CalendarDayTodo(
          id: '740',
          title: 'WordyGo application',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '07:40',
          minutesSinceMidnight: 460,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, detail, now: DateTime(2026, 6, 26, 6, 58));

    final currentTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-current-time-line')))
        .dy;
    final sevenTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-mark-420')))
        .dy;

    expect(find.byKey(const ValueKey('calendar-hour-label-420')), findsNothing);
    expect(currentTop, lessThanOrEqualTo(sevenTop - 12));
  });

  testWidgets(
    'off-mark todo in a half hour stays close to the half-hour line',
    (tester) async {
      final detail = _detail(
        currentVisible: false,
        timedTodos: const [
          CalendarDayTodo(
            id: '710',
            title: 'Todo đầu giờ',
            status: 'open',
            position: 1,
            scheduledDate: null,
            time: '07:10',
            minutesSinceMidnight: 430,
            isFrog: false,
            isImportant: false,
            isUrgent: false,
            hasSubtasks: false,
          ),
          CalendarDayTodo(
            id: '740',
            title: 'WordyGo application',
            status: 'open',
            position: 2,
            scheduledDate: null,
            time: '07:40',
            minutesSinceMidnight: 460,
            isFrog: false,
            isImportant: false,
            isUrgent: false,
            hasSubtasks: false,
          ),
        ],
      );

      await _pumpTimeline(tester, detail);

      final halfHourTop = tester
          .getTopLeft(
            find.byKey(const ValueKey('calendar-half-hour-label-450')),
          )
          .dy;
      final todoTop = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-todo-740')))
          .dy;

      expect(todoTop - halfHourTop, inInclusiveRange(6, 10));
    },
  );

  testWidgets('occupied hour height fits the number of todos', (tester) async {
    final oneTodoDetail = _detail(
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: 'gym',
          title: 'Go to GYM',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '13:00',
          minutesSinceMidnight: 780,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, oneTodoDetail);

    final thirteenTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-780')))
        .dy;
    final fourteenTop = tester
        .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-840')))
        .dy;
    final todoBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('calendar-todo-gym')))
        .dy;

    expect(
      find.byKey(const ValueKey('calendar-half-hour-label-810')),
      findsNothing,
    );
    expect(fourteenTop - thirteenTop, lessThan(100));
    expect(fourteenTop - todoBottom, inInclusiveRange(6, 40));

    final twoTodosDetail = _detail(
      currentVisible: false,
      timedTodos: const [
        CalendarDayTodo(
          id: 'gym-a',
          title: 'Go to GYM',
          status: 'open',
          position: 1,
          scheduledDate: null,
          time: '13:00',
          minutesSinceMidnight: 780,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
        CalendarDayTodo(
          id: 'gym-b',
          title: 'Protein',
          status: 'open',
          position: 2,
          scheduledDate: null,
          time: '13:00',
          minutesSinceMidnight: 780,
          isFrog: false,
          isImportant: false,
          isUrgent: false,
          hasSubtasks: false,
        ),
      ],
    );

    await _pumpTimeline(tester, twoTodosDetail);

    final oneHourHeight = fourteenTop - thirteenTop;
    final twoHourHeight =
        tester
            .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-840')))
            .dy -
        tester
            .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-780')))
            .dy;

    expect(twoHourHeight, greaterThan(oneHourHeight));
    expect(twoHourHeight, lessThan(170));
  });

  testWidgets(
    'current time keeps compact empty half-hour readable before next todo',
    (tester) async {
      final detail = _detail(
        currentVisible: true,
        timedTodos: const [
          CalendarDayTodo(
            id: 'done-9h',
            title: 'Train typing',
            status: 'done',
            position: 1,
            scheduledDate: null,
            time: '09:00',
            minutesSinceMidnight: 540,
            isFrog: false,
            isImportant: false,
            isUrgent: false,
            hasSubtasks: false,
          ),
          CalendarDayTodo(
            id: 'open-10h',
            title: 'WordyGo application',
            status: 'open',
            position: 2,
            scheduledDate: null,
            time: '10:00',
            minutesSinceMidnight: 600,
            estimatedMinutes: 60,
            isFrog: false,
            isImportant: false,
            isUrgent: false,
            hasSubtasks: false,
          ),
        ],
      );

      await _pumpTimeline(tester, detail, now: DateTime(2026, 6, 26, 9, 56));

      final currentLineTop = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-current-time-line')))
          .dy;
      final nextTodoTop = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-todo-open-10h')))
          .dy;

      expect(find.text('09:56'), findsOneWidget);
      expect(nextTodoTop - currentLineTop, greaterThanOrEqualTo(16));
    },
  );

  testWidgets(
    'untimed todos render outside timeline and non-today hides line',
    (tester) async {
      final detail = _detail(
        date: DateTime(2026, 6, 27),
        currentVisible: false,
        untimedTodos: const [
          CalendarDayTodo(
            id: 'no-time',
            title: 'Không có giờ',
            status: 'open',
            position: 1,
            scheduledDate: null,
            time: null,
            isFrog: false,
            isImportant: false,
            isUrgent: false,
            hasSubtasks: false,
          ),
        ],
      );

      await _pumpTimeline(tester, detail);

      expect(find.text('Không có giờ'), findsWidgets);
      expect(
        find.byKey(const ValueKey('calendar-untimed-todo-no-time')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-current-time-line')),
        findsNothing,
      );
    },
  );

  group('centering the current time line', () {
    final todo = const CalendarDayTodo(
      id: 'noon',
      title: 'Việc buổi trưa',
      status: 'open',
      position: 1,
      scheduledDate: null,
      time: '12:00',
      minutesSinceMidnight: 720,
      isFrog: false,
      isImportant: false,
      isUrgent: false,
      hasSubtasks: false,
    );

    Future<void> pump(
      WidgetTester tester, {
      required CalendarDayDetail detail,
      required bool center,
      DateTime? now,
    }) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                CalendarDayTimeline(
                  key: const ValueKey('timeline'),
                  detail: detail,
                  now: now ?? DateTime(2026, 6, 26, 16, 44),
                  centerCurrentTimeOnShow: center,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    double offset(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    testWidgets('puts the red line in the middle of the viewport', (
      tester,
    ) async {
      await pump(
        tester,
        detail: _detail(currentVisible: true, timedTodos: [todo]),
        center: true,
      );

      final lineCenter = tester
          .getCenter(find.byKey(const ValueKey('calendar-current-time-line')))
          .dy;
      final viewportCenter = tester.getCenter(find.byType(ListView)).dy;

      expect(offset(tester), greaterThan(0));
      expect(lineCenter, closeTo(viewportCenter, 12));
    });

    testWidgets('does nothing unless requested', (tester) async {
      await pump(
        tester,
        detail: _detail(currentVisible: true, timedTodos: [todo]),
        center: false,
      );

      expect(offset(tester), 0);
    });

    testWidgets('does nothing for a day without the red line', (tester) async {
      await pump(
        tester,
        detail: _detail(currentVisible: false, timedTodos: [todo]),
        center: true,
      );

      expect(offset(tester), 0);
    });

    testWidgets('centers only once, later rebuilds keep the user position', (
      tester,
    ) async {
      final detail = _detail(currentVisible: true, timedTodos: [todo]);
      await pump(tester, detail: detail, center: true);
      expect(offset(tester), greaterThan(0));

      tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                CalendarDayTimeline(
                  key: const ValueKey('timeline'),
                  detail: detail,
                  now: DateTime(2026, 6, 26, 16, 45),
                  centerCurrentTimeOnShow: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(offset(tester), 0);
    });
  });

  group('two-line title with meta chips', () {
    const longTitle =
        'Hoàn thiện báo cáo tổng kết quý và gửi cho toàn bộ các bên liên quan';

    testWidgets('card grows instead of overflowing when duration is set', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final detail = _detail(
        currentVisible: false,
        timedTodos: const [
          CalendarDayTodo(
            id: 'long',
            title: longTitle,
            status: 'open',
            position: 1,
            scheduledDate: null,
            time: '09:00',
            minutesSinceMidnight: 540,
            estimatedMinutes: 30,
            isFrog: false,
            isImportant: false,
            isUrgent: false,
            hasSubtasks: true,
          ),
          CalendarDayTodo(
            id: 'next',
            title: 'Việc kế tiếp',
            status: 'open',
            position: 2,
            scheduledDate: null,
            time: '10:00',
            minutesSinceMidnight: 600,
            isFrog: false,
            isImportant: false,
            isUrgent: false,
            hasSubtasks: false,
          ),
        ],
      );

      await _pumpTimeline(tester, detail);

      expect(tester.takeException(), isNull);

      final longSize = tester.getSize(
        find.byKey(const ValueKey('calendar-todo-long')),
      );
      final longBottom = tester
          .getBottomLeft(find.byKey(const ValueKey('calendar-todo-long')))
          .dy;
      final nextTop = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-todo-next')))
          .dy;

      expect(longSize.height, greaterThan(60));
      expect(nextTop, greaterThanOrEqualTo(longBottom));
    });

    testWidgets('same-time todos stack without overlap or overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final detail = _detail(
        currentVisible: false,
        timedTodos: const [
          CalendarDayTodo(
            id: 'long',
            title: longTitle,
            status: 'open',
            position: 1,
            scheduledDate: null,
            time: '09:00',
            minutesSinceMidnight: 540,
            isFrog: false,
            isImportant: false,
            isUrgent: false,
            hasSubtasks: true,
          ),
          CalendarDayTodo(
            id: 'short',
            title: 'Việc ngắn',
            status: 'open',
            position: 2,
            scheduledDate: null,
            time: '09:00',
            minutesSinceMidnight: 540,
            isFrog: false,
            isImportant: false,
            isUrgent: false,
            hasSubtasks: false,
          ),
        ],
      );

      await _pumpTimeline(tester, detail);

      expect(tester.takeException(), isNull);

      final longBottom = tester
          .getBottomLeft(find.byKey(const ValueKey('calendar-todo-long')))
          .dy;
      final shortTop = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-todo-short')))
          .dy;
      final shortBottom = tester
          .getBottomLeft(find.byKey(const ValueKey('calendar-todo-short')))
          .dy;
      final tenTop = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-hour-label-600')))
          .dy;

      expect(shortTop, greaterThanOrEqualTo(longBottom));
      expect(shortBottom, lessThanOrEqualTo(tenTop));
    });
  });
}

Future<void> _pumpTimeline(
  WidgetTester tester,
  CalendarDayDetail detail, {
  DateTime? now,
  ValueChanged<CalendarDayTodo>? onTodoTap,
  ValueChanged<CalendarDayTodo>? onTodoComplete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CalendarDayTimeline(
            detail: detail,
            now: now ?? DateTime(2026, 6, 26, 16, 44),
            minuteHeight: 1,
            onTodoTap: onTodoTap,
            onTodoComplete: onTodoComplete,
          ),
        ),
      ),
    ),
  );
}

Finder _richTextContaining(String value) {
  return find.byWidgetPredicate((widget) {
    if (widget is! RichText) return false;
    return widget.text.toPlainText().contains(value);
  });
}

CalendarDayDetail _detail({
  DateTime? date,
  required bool currentVisible,
  List<CalendarDayTodo> timedTodos = const [],
  List<CalendarDayTodo> untimedTodos = const [],
}) {
  final selectedDate = date ?? DateTime(2026, 6, 26);
  return CalendarDayDetail(
    date: selectedDate,
    timezone: 'Asia/Ho_Chi_Minh',
    week: CalendarWeek.fromJson(null, selectedDate: selectedDate),
    timeline: CalendarTimeline(
      startMinute: 0,
      endMinute: 1440,
      slotMinutes: 60,
      hourMarks: List.generate(25, (index) {
        final minute = index * 60;
        final labelHour = minute == 1440 ? 0 : index;
        return CalendarHourMark(
          minute: minute,
          label: '${labelHour.toString().padLeft(2, '0')}:00',
        );
      }),
    ),
    currentTimeIndicator: currentVisible
        ? const CalendarCurrentTimeIndicator(
            visible: true,
            currentTime: '16:44',
            minutesSinceMidnight: 1004,
            lineMinutesSinceMidnight: 1004,
            hiddenHourMarkMinute: 1020,
            hiddenHourLabel: '17:00',
          )
        : CalendarCurrentTimeIndicator.hidden,
    timedTodos: timedTodos,
    untimedTodos: untimedTodos,
    totals: CalendarDayTotals(
      totalTodos: timedTodos.length + untimedTodos.length,
      timedTodos: timedTodos.length,
      untimedTodos: untimedTodos.length,
      doneTodos:
          timedTodos.where((todo) => todo.isDone).length +
          untimedTodos.where((todo) => todo.isDone).length,
    ),
  );
}
