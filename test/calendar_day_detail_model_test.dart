import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/api_config.dart';
import 'package:todonote/models/dashboard.dart';

void main() {
  test('calendar day detail endpoint URI uses api v1 path and date query', () {
    final uri = ApiConfig.resolveApiUri('/dashboard/calendar/day', const {
      'date': '2026-06-26',
    });

    expect(
      uri.toString(),
      'https://todosnotes.onrender.com/api/v1/dashboard/calendar/day?date=2026-06-26',
    );
  });

  test('calendar day detail parses timed and untimed todos safely', () {
    final detail = CalendarDayDetail.fromJson({
      'date': '2026-06-26',
      'timezone': 'Asia/Ho_Chi_Minh',
      'week': {
        'starts_on': 'monday',
        'from': '2026-06-22',
        'to': '2026-06-28',
        'days': List.generate(7, (index) {
          final day = 22 + index;
          return {
            'date': '2026-06-${day.toString().padLeft(2, '0')}',
            'iso_weekday': index + 1,
            'weekday_label': index == 6 ? 'CN' : 'T${index + 2}',
            'day_of_month': day,
            'month': 6,
            'is_selected': day == 26,
            'is_today': day == 26,
            'total_todos': day == 26 ? 3 : 0,
            'timed_todos': day == 26 ? 2 : 0,
            'done_todos': day == 26 ? 1 : 0,
          };
        }),
      },
      'timeline': {
        'start_minute': 0,
        'end_minute': 1440,
        'slot_minutes': 60,
        'hour_marks': [
          {'minute': 0, 'label': '00:00'},
          {'minute': 540, 'label': '09:00'},
          {'minute': 1080, 'label': '18:00'},
          {'minute': 1440, 'label': '00:00'},
        ],
      },
      'current_time_indicator': {
        'visible': true,
        'server_time': '2026-06-26T09:44:00.000Z',
        'current_date': '2026-06-26',
        'current_time': '16:44',
        'minutes_since_midnight': 1004,
        'line_minutes_since_midnight': 1004,
        'hidden_hour_mark_minute': 1020,
        'hidden_hour_label': '17:00',
      },
      'timed_todos': [
        {
          'id': '18h',
          'user_id': 'user-1',
          'parent_id': null,
          'title': 'Todo lúc 18h',
          'description': null,
          'status': 'open',
          'position': 2,
          'scheduled_date': '2026-06-26',
          'time': '18:00',
          'minutes_since_midnight': 1080,
          'estimated_minutes': 45,
          'actual_minutes': null,
          'start_at': null,
          'due_at': null,
          'completed_at': null,
          'is_frog': true,
          'frog_date': '2026-06-26',
          'is_important': true,
          'is_urgent': false,
          'trigger_after_todo_id': null,
          'habit_id': null,
          'recurrence_type': null,
          'recurrence_interval': null,
          'recurrence_days_of_week': null,
          'recurrence_end_date': null,
          'recurrence_template_id': null,
          'has_subtasks': true,
          'tags': [
            {'id': 'tag-1', 'name': 'Work', 'color': '#3366ff'},
          ],
          'tag_ids': ['tag-1'],
          'created_at': '2026-06-26T00:00:00.000Z',
          'updated_at': '2026-06-26T00:00:00.000Z',
        },
        {
          'id': '9h',
          'title': 'Todo lúc 9h',
          'status': 'done',
          'position': 1,
          'scheduled_date': '2026-06-26',
          'time': '09:00',
          'minutes_since_midnight': 540,
        },
        {
          'id': 'subtask-ignored',
          'parent_id': '18h',
          'title': 'Subtask',
          'status': 'open',
          'time': '08:00',
        },
      ],
      'untimed_todos': [
        {
          'id': 'no-time',
          'title': 'Không có giờ',
          'status': 'open',
          'position': 3,
          'scheduled_date': '2026-06-26',
          'time': null,
        },
      ],
      'totals': {
        'total_todos': 3,
        'timed_todos': 2,
        'untimed_todos': 1,
        'done_todos': 1,
      },
      'future_field': {'ignored': true},
    });

    expect(detail.date, DateTime(2026, 6, 26));
    expect(detail.week.days, hasLength(7));
    expect(detail.week.days.first.weekdayLabel, 'T2');
    expect(detail.week.days.last.weekdayLabel, 'CN');
    expect(detail.currentTimeIndicator.hiddenHourMarkMinute, 1020);
    expect(detail.currentTimeIndicator.hiddenHourLabel, '17:00');
    expect(detail.timedTodos.map((todo) => todo.id), ['9h', '18h']);
    expect(detail.timedTodos.last.minutesSinceMidnight, 1080);
    expect(detail.timedTodos.last.tags.single.name, 'Work');
    expect(detail.untimedTodos.single.id, 'no-time');
    expect(detail.totals.doneTodos, 1);
  });

  test('calendar day detail tolerates missing sections', () {
    final detail = CalendarDayDetail.fromJson({'date': '2026-06-26'});

    expect(detail.timeline.hourMarks.first.label, '00:00');
    expect(detail.timeline.hourMarks.last.minute, 1440);
    expect(detail.week.days, hasLength(7));
    expect(detail.timedTodos, isEmpty);
    expect(detail.untimedTodos, isEmpty);
    expect(detail.totals.totalTodos, 0);
    expect(detail.currentTimeIndicator.visible, isFalse);
  });

  test(
    'calendar day detail parses daily log metadata and locked completion',
    () {
      final detail = CalendarDayDetail.fromJson({
        'date': '2026-06-20',
        'timed_todos': [
          {
            'id': 'todo-live-id',
            'source': 'daily_log',
            'is_daily_log': true,
            'log_id': 'log-1',
            'todo_id': 'todo-live-id',
            'locked_completed': false,
            'title': 'Hoàn thành muộn',
            'status': 'done',
            'scheduled_date': '2026-06-20',
            'time': '09:00',
            'minutes_since_midnight': 540,
            'is_frog': false,
            'is_important': null,
            'is_urgent': null,
            'has_subtasks': false,
            'tags': [],
            'tag_ids': [],
          },
        ],
        'totals': {
          'total_todos': 6,
          'timed_todos': 1,
          'untimed_todos': 0,
          'done_todos': 3,
        },
      });

      final todo = detail.timedTodos.single;
      expect(todo.source, 'daily_log');
      expect(todo.isDailyLog, isTrue);
      expect(todo.logId, 'log-1');
      expect(todo.todoId, 'todo-live-id');
      expect(todo.lockedCompleted, isFalse);
      expect(todo.status, 'done');
      expect(todo.isDone, isFalse);
      expect(todo.tags, isEmpty);
      expect(todo.tagIds, isEmpty);
      expect(detail.totals.doneTodos, 3);
      expect(detail.totals.totalTodos, 6);
    },
  );
}
