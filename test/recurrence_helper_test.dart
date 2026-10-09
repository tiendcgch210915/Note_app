import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/tag.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/utils/recurrence_helper.dart';
import 'package:todonote/widgets/repeat_picker_sheet.dart';

void main() {
  test('nextDateAfterCompletedTodo handles daily and custom intervals', () {
    final daily = Todo(
      id: 'daily-1',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 15),
      recurrenceType: 'daily',
      recurrenceInterval: 2,
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );
    final custom = Todo(
      id: 'custom-1',
      title: 'Custom review',
      scheduledDate: DateTime(2026, 6, 15),
      recurrenceType: 'custom',
      recurrenceInterval: 3,
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );

    expect(
      RecurrenceHelper.nextDateAfterCompletedTodo(daily),
      DateTime.utc(2026, 6, 17),
    );
    expect(
      RecurrenceHelper.nextDateAfterCompletedTodo(custom),
      DateTime.utc(2026, 6, 18),
    );
  });

  test('nextDateAfterCompletedTodo handles weekly ISO weekdays', () {
    final sameWeek = Todo(
      id: 'weekly-1',
      title: 'Weekly review',
      scheduledDate: DateTime(2026, 6, 17), // Wednesday
      recurrenceType: 'weekly',
      recurrenceInterval: 1,
      recurrenceDaysOfWeek: '1,3,5',
      createdAt: DateTime.utc(2026, 6, 17),
      updatedAt: DateTime.utc(2026, 6, 17),
    );
    final nextCycle = Todo(
      id: 'weekly-2',
      title: 'Weekly review',
      scheduledDate: DateTime(2026, 6, 19), // Friday
      recurrenceType: 'weekly',
      recurrenceInterval: 2,
      recurrenceDaysOfWeek: '1,3,5',
      createdAt: DateTime.utc(2026, 6, 19),
      updatedAt: DateTime.utc(2026, 6, 19),
    );
    final fallback = Todo(
      id: 'weekly-3',
      title: 'Weekly review',
      scheduledDate: DateTime(2026, 6, 17),
      recurrenceType: 'weekly',
      recurrenceInterval: 2,
      createdAt: DateTime.utc(2026, 6, 17),
      updatedAt: DateTime.utc(2026, 6, 17),
    );

    expect(
      RecurrenceHelper.nextDateAfterCompletedTodo(sameWeek),
      DateTime.utc(2026, 6, 19),
    );
    expect(
      RecurrenceHelper.nextDateAfterCompletedTodo(nextCycle),
      DateTime.utc(2026, 6, 29),
    );
    expect(
      RecurrenceHelper.nextDateAfterCompletedTodo(fallback),
      DateTime.utc(2026, 7, 1),
    );
  });

  test('nextDateAfterCompletedTodo respects recurrence end date', () {
    final todo = Todo(
      id: 'daily-end',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 15),
      recurrenceType: 'daily',
      recurrenceInterval: 1,
      recurrenceEndDate: '2026-06-15',
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );

    expect(RecurrenceHelper.nextDateAfterCompletedTodo(todo), isNull);
  });

  test('nextDateOnOrAfter skips missed daily occurrences', () {
    final todo = Todo(
      id: 'legacy-daily',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 10),
      recurrenceType: 'daily',
      recurrenceInterval: 2,
      createdAt: DateTime.utc(2026, 6, 10),
      updatedAt: DateTime.utc(2026, 6, 10),
    );

    expect(
      RecurrenceHelper.nextDateOnOrAfter(
        todo: todo,
        minimumDate: DateTime(2026, 6, 17),
      ),
      DateTime.utc(2026, 6, 18),
    );
  });

  test('nextDateOnOrAfter stops when legacy series has ended', () {
    final todo = Todo(
      id: 'legacy-ended',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 10),
      recurrenceType: 'daily',
      recurrenceInterval: 1,
      recurrenceEndDate: '2026-06-15',
      createdAt: DateTime.utc(2026, 6, 10),
      updatedAt: DateTime.utc(2026, 6, 10),
    );

    expect(
      RecurrenceHelper.nextDateOnOrAfter(
        todo: todo,
        minimumDate: DateTime(2026, 6, 17),
      ),
      isNull,
    );
  });

  test('nextDateSkippingExceptions never recreates deleted occurrence', () {
    final todo = Todo(
      id: 'daily-exception',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 17),
      recurrenceType: 'daily',
      recurrenceInterval: 1,
      createdAt: DateTime.utc(2026, 6, 17),
      updatedAt: DateTime.utc(2026, 6, 17),
    );

    expect(
      RecurrenceHelper.nextDateSkippingExceptions(
        todo: todo,
        exceptionDates: const {'2026-06-18', '2026-06-19'},
      ),
      DateTime.utc(2026, 6, 20),
    );
  });

  test(
    'buildNextAfterCompletion copies recurrence data and resets completion',
    () {
      final tag = Tag(
        id: 'tag-1',
        name: 'Work',
        color: const Color(0xFF3366FF),
      );
      final source = Todo(
        id: 'todo-1',
        title: 'Daily habit todo',
        description: 'Original description',
        status: TodoStatus.done,
        scheduledDate: DateTime(2026, 6, 15),
        dueAt: DateTime.utc(2026, 6, 15, 23, 59),
        isFrog: true,
        frogDate: DateTime(2026, 6, 15),
        isImportant: true,
        isUrgent: false,
        estimatedMinutes: 15,
        actualMinutes: 12,
        habitId: 'habit-1',
        tags: [tag],
        tagIds: const ['tag-1'],
        tagsLoaded: true,
        completedAt: DateTime.utc(2026, 6, 15, 8),
        recurrenceType: 'daily',
        recurrenceInterval: 1,
        recurrenceEndDate: '2026-06-30',
        createdAt: DateTime.utc(2026, 6, 15),
        updatedAt: DateTime.utc(2026, 6, 15),
      );

      final next = RecurrenceHelper.buildNextAfterCompletion(
        source: source,
        scheduledDate: DateTime.utc(2026, 6, 16),
        templateId: source.id,
        overrideId: 'next-1',
        tags: [tag],
        tagIds: const ['tag-1'],
      );

      expect(next.id, 'next-1');
      expect(next.status, TodoStatus.open);
      expect(next.completedAt, isNull);
      expect(next.actualMinutes, isNull);
      expect(next.scheduledDate, DateTime.utc(2026, 6, 16));
      expect(next.dueAt, DateTime.utc(2026, 6, 16, 23, 59));
      expect(next.habitId, 'habit-1');
      expect(next.tagIds, ['tag-1']);
      expect(next.recurrenceType, 'daily');
      expect(next.recurrenceTemplateId, source.id);
    },
  );

  test('buildInstance sets dueAt to the same date end of day', () {
    final template = Todo(
      id: 'template-1',
      title: 'Daily review',
      scheduledDate: DateTime(2026, 6, 15),
      recurrenceType: 'daily',
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );

    final instance = RecurrenceHelper.buildInstance(
      template: template,
      date: DateTime.utc(2026, 6, 16),
      overrideId: 'instance-1',
    );

    expect(instance.scheduledDate, DateTime.utc(2026, 6, 16));
    expect(instance.dueAt, DateTime.utc(2026, 6, 16, 23, 59));
    expect(instance.recurrenceTemplateId, 'template-1');
    expect(instance.recurrenceType, isNull);
  });

  test('buildInstance copies template tags', () {
    final tag = Tag(id: 'tag-1', name: 'Work', color: const Color(0xFF3366FF));
    final template = Todo(
      id: 'template-1',
      title: 'Daily review',
      recurrenceType: 'daily',
      tags: [tag],
      tagIds: const ['tag-1'],
      tagsLoaded: true,
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );

    final instance = RecurrenceHelper.buildInstance(
      template: template,
      date: DateTime.utc(2026, 6, 16),
    );

    expect(instance.tags, [tag]);
    expect(instance.tagIds, ['tag-1']);
    expect(instance.tagsLoaded, isTrue);
  });

  test('buildInstance copies template habit link', () {
    final template = Todo(
      id: 'template-1',
      title: 'Daily habit todo',
      recurrenceType: 'daily',
      time: '08:30',
      habitId: 'habit-1',
      createdAt: DateTime.utc(2026, 6, 15),
      updatedAt: DateTime.utc(2026, 6, 15),
    );

    final instance = RecurrenceHelper.buildInstance(
      template: template,
      date: DateTime.utc(2026, 6, 16),
    );

    expect(instance.habitId, 'habit-1');
    expect(instance.time, '08:30');
  });

  group('next date matches the backend (nextRecurrenceDate)', () {
    // Backend: Todo_Note/src/services/todos.ts `nextRecurrenceDate`.
    // Hai phía phải ra CÙNG một ngày, nếu không mỗi bên tạo một slot riêng và
    // series bị trùng. Tháng 6/2026: 15=T2 16=T3 17=T4 18=T5 19=T6 20=T7 21=CN.
    final mon = DateTime(2026, 6, 15);
    final fri = DateTime(2026, 6, 19);
    final sun = DateTime(2026, 6, 21);

    Todo rule(
      String type,
      DateTime from, {
      int interval = 1,
      String? days,
      String? end,
    }) {
      return Todo(
        id: 'series',
        title: 'Series',
        scheduledDate: from,
        recurrenceType: type,
        recurrenceInterval: interval,
        recurrenceDaysOfWeek: days,
        recurrenceEndDate: end,
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
      );
    }

    // Kỳ vọng tính tay. Với weekly có chọn ngày mà hết tuần:
    //   +(7 - thứ_hiện_tại + (interval - 1) * 7 + ngày_đầu_tiên) ngày.
    final cases = <(String, Todo, DateTime)>[
      // daily / custom: +interval ngày (qua tháng, năm, năm nhuận).
      ('daily 1', rule('daily', mon), DateTime.utc(2026, 6, 16)),
      ('daily 3', rule('daily', mon, interval: 3), DateTime.utc(2026, 6, 18)),
      (
        'daily sang tháng',
        rule('daily', DateTime(2026, 6, 30)),
        DateTime.utc(2026, 7, 1),
      ),
      (
        'daily 3 sang tháng',
        rule('daily', DateTime(2026, 6, 29), interval: 3),
        DateTime.utc(2026, 7, 2),
      ),
      (
        'daily sang năm',
        rule('daily', DateTime(2026, 12, 31)),
        DateTime.utc(2027, 1, 1),
      ),
      (
        'daily 28/2 năm nhuận',
        rule('daily', DateTime(2028, 2, 28)),
        DateTime.utc(2028, 2, 29),
      ),
      (
        'daily 29/2 năm nhuận',
        rule('daily', DateTime(2028, 2, 29)),
        DateTime.utc(2028, 3, 1),
      ),
      ('custom 2', rule('custom', mon, interval: 2), DateTime.utc(2026, 6, 17)),
      (
        // Backend bỏ qua ngày trong tuần của custom: luôn +interval.
        'custom có days vẫn +interval',
        rule('custom', mon, interval: 2, days: '1,3'),
        DateTime.utc(2026, 6, 17),
      ),
      (
        'interval 0 coi như 1',
        rule('daily', mon, interval: 0),
        DateTime.utc(2026, 6, 16),
      ),

      // weekly không chọn ngày: +7 × interval.
      ('weekly 1', rule('weekly', mon), DateTime.utc(2026, 6, 22)),
      ('weekly 2', rule('weekly', mon, interval: 2), DateTime.utc(2026, 6, 29)),

      // weekly "1,3,5" (T2, T4, T6).
      (
        'weekly 1,3,5 từ T2 → T4',
        rule('weekly', mon, days: '1,3,5'),
        DateTime.utc(2026, 6, 17),
      ),
      (
        'weekly 1,3,5 từ T6 → T2 tuần sau',
        rule('weekly', fri, days: '1,3,5'),
        DateTime.utc(2026, 6, 22),
      ),
      (
        'weekly 1,3,5 từ CN → T2 tuần sau',
        rule('weekly', sun, days: '1,3,5'),
        DateTime.utc(2026, 6, 22),
      ),
      (
        'weekly 1,3,5 interval 2 từ T2 (cùng tuần) → T4',
        rule('weekly', mon, interval: 2, days: '1,3,5'),
        DateTime.utc(2026, 6, 17),
      ),
      (
        'weekly 1,3,5 interval 2 từ T6 → T2 sau 2 tuần',
        rule('weekly', fri, interval: 2, days: '1,3,5'),
        DateTime.utc(2026, 6, 29),
      ),
      (
        'weekly 1,3,5 interval 2 từ CN → T2 sau 2 tuần',
        rule('weekly', sun, interval: 2, days: '1,3,5'),
        DateTime.utc(2026, 6, 29),
      ),

      // weekly "2" (chỉ T3).
      (
        'weekly 2 từ T2 → T3',
        rule('weekly', mon, days: '2'),
        DateTime.utc(2026, 6, 16),
      ),
      (
        'weekly 2 từ T6 → T3 tuần sau',
        rule('weekly', fri, days: '2'),
        DateTime.utc(2026, 6, 23),
      ),
      (
        'weekly 2 từ CN → T3 tuần sau',
        rule('weekly', sun, days: '2'),
        DateTime.utc(2026, 6, 23),
      ),
      (
        'weekly 2 interval 2 từ T2 → T3 cùng tuần',
        rule('weekly', mon, interval: 2, days: '2'),
        DateTime.utc(2026, 6, 16),
      ),
      (
        'weekly 2 interval 2 từ T6 → T3 sau 2 tuần',
        rule('weekly', fri, interval: 2, days: '2'),
        DateTime.utc(2026, 6, 30),
      ),
      (
        'weekly 2 interval 2 từ CN → T3 sau 2 tuần',
        rule('weekly', sun, interval: 2, days: '2'),
        DateTime.utc(2026, 6, 30),
      ),

      // Chuỗi ngày không sạch: backend lọc, sắp xếp, bỏ trùng.
      (
        'days lộn xộn "5,1,1,9,x" = {1,5}',
        rule('weekly', mon, days: '5,1,1,9,x'),
        DateTime.utc(2026, 6, 19),
      ),
      (
        'days có khoảng trắng " 3 , 5 "',
        rule('weekly', mon, days: ' 3 , 5 '),
        DateTime.utc(2026, 6, 17),
      ),
      (
        'days toàn rác = không chọn ngày',
        rule('weekly', mon, days: 'x,0,8'),
        DateTime.utc(2026, 6, 22),
      ),

      // recurrence_end_date: ngày kế tiếp > end thì dừng (bằng end vẫn được).
      (
        'daily đúng ngày end vẫn tạo',
        rule('daily', mon, end: '2026-06-16'),
        DateTime.utc(2026, 6, 16),
      ),
    ];

    for (final (label, todo, expected) in cases) {
      test(label, () {
        expect(RecurrenceHelper.nextDateAfterCompletedTodo(todo), expected);
      });
    }

    test('vượt recurrence_end_date thì không còn occurrence kế tiếp', () {
      expect(
        RecurrenceHelper.nextDateAfterCompletedTodo(
          rule('daily', mon, end: '2026-06-15'),
        ),
        isNull,
      );
      expect(
        RecurrenceHelper.nextDateAfterCompletedTodo(
          rule('weekly', fri, days: '1,3,5', end: '2026-06-21'),
        ),
        isNull,
      );
      expect(
        RecurrenceHelper.nextDateAfterCompletedTodo(
          rule('weekly', fri, days: '1,3,5', end: '2026-06-22'),
        ),
        DateTime.utc(2026, 6, 22),
      );
    });

    test('thiếu ngày hoặc loại lặp thì không có ngày kế tiếp', () {
      final noDate = Todo(
        id: 'x',
        title: 'x',
        recurrenceType: 'daily',
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
      );
      final noRule = Todo(
        id: 'y',
        title: 'y',
        scheduledDate: mon,
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
      );
      expect(RecurrenceHelper.nextDateAfterCompletedTodo(noDate), isNull);
      expect(RecurrenceHelper.nextDateAfterCompletedTodo(noRule), isNull);
    });

    group('ngày ngoại lệ (tombstone) bị bỏ qua như resolveNextSlot', () {
      test('daily nhảy qua các ngày đã xóa', () {
        expect(
          RecurrenceHelper.nextDateSkippingExceptions(
            todo: rule('daily', DateTime(2026, 6, 17)),
            exceptionDates: const {'2026-06-18', '2026-06-19'},
          ),
          DateTime.utc(2026, 6, 20),
        );
      });

      test('weekly bỏ qua T6 đã xóa và rơi sang T2 tuần sau', () {
        expect(
          RecurrenceHelper.nextDateSkippingExceptions(
            todo: rule('weekly', DateTime(2026, 6, 17), days: '1,3,5'),
            exceptionDates: const {'2026-06-19'},
          ),
          DateTime.utc(2026, 6, 22),
        );
      });

      test('ngày ngoại lệ không nằm trên đường đi thì không ảnh hưởng', () {
        expect(
          RecurrenceHelper.nextDateSkippingExceptions(
            todo: rule('daily', mon, interval: 2),
            exceptionDates: const {'2026-06-16', '2026-06-18'},
          ),
          DateTime.utc(2026, 6, 17),
        );
      });

      test('ngoại lệ đẩy ngày kế tiếp quá end thì dừng', () {
        expect(
          RecurrenceHelper.nextDateSkippingExceptions(
            todo: rule('daily', DateTime(2026, 6, 17), end: '2026-06-19'),
            exceptionDates: const {'2026-06-18', '2026-06-19'},
          ),
          isNull,
        );
      });
    });

    test('quét 61 ngày × luật × interval khớp bản port của backend', () {
      final mismatches = <String>[];
      var checked = 0;
      for (final type in const ['daily', 'weekly', 'custom']) {
        for (final interval in const [0, 1, 2, 3]) {
          for (final days in const [
            null,
            '',
            '1,3,5',
            '2',
            '7',
            '1,7',
            '5,1,1,9,x',
            ' 3 , 5 ',
          ]) {
            for (final end in const [null, '2026-07-15']) {
              for (var offset = 0; offset < 61; offset++) {
                final from = DateTime(2026, 6, 1 + offset);
                final mobile = RecurrenceHelper.nextDateAfterCompletedTodo(
                  rule(type, from, interval: interval, days: days, end: end),
                );
                final backend = _backendNextRecurrenceDate(
                  type: type,
                  interval: interval,
                  days: days,
                  scheduled: _iso(from),
                  end: end,
                );
                checked++;
                final mobileIso = mobile == null ? null : _iso(mobile);
                if (mobileIso != backend) {
                  mismatches.add(
                    '$type/$interval/${days ?? '-'}/${end ?? '-'} '
                    'từ ${_iso(from)}: mobile=$mobileIso backend=$backend',
                  );
                }
              }
            }
          }
        }
      }
      expect(checked, 3 * 4 * 8 * 2 * 61);
      expect(mismatches, isEmpty, reason: mismatches.take(10).join('\n'));
    });
  });

  group('Todo.activeDaysOfWeek', () {
    Todo withDays(String? days) => Todo(
      id: 'd',
      title: 'd',
      recurrenceType: 'weekly',
      recurrenceDaysOfWeek: days,
      createdAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 1),
    );

    test('lọc rác, bỏ trùng, sắp xếp thay vì ném lỗi', () {
      expect(withDays(null).activeDaysOfWeek, isEmpty);
      expect(withDays('').activeDaysOfWeek, isEmpty);
      expect(withDays('1,3,5').activeDaysOfWeek, [1, 3, 5]);
      expect(withDays('5,1,1,9,x,0').activeDaysOfWeek, [1, 5]);
      expect(withDays(' 3 , 5 ').activeDaysOfWeek, [3, 5]);
    });

    test('nhãn lặp lại không văng RangeError với ngày ngoài 1..7', () {
      expect(withDays('9,2').recurrenceLabel, 'T3');
    });

    test('trình chọn lặp lại đọc chuỗi ngày giống Todo.activeDaysOfWeek', () {
      const junk = RepeatSettings(type: 'weekly', daysOfWeek: '5,1,1,9,x, 3 ');
      expect(junk.activeDays, [1, 3, 5]);
      expect(junk.activeDays, withDays('5,1,1,9,x, 3 ').activeDaysOfWeek);
      expect(const RepeatSettings(type: 'weekly').activeDays, isEmpty);
      expect(
        const RepeatSettings(type: 'weekly', daysOfWeek: '9').label,
        'Mỗi tuần',
      );
    });
  });
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Bản port nguyên văn của `nextRecurrenceDate` (Todo_Note/src/services/todos.ts)
/// để đối chiếu chéo. Không dùng lại code Mobile ở đây.
String? _backendNextRecurrenceDate({
  required String type,
  required int interval,
  required String? days,
  required String scheduled,
  required String? end,
}) {
  String addDays(String date, int n) =>
      _iso(DateTime.parse('${date}T00:00:00Z').add(Duration(days: n)));
  int isoWeekday(String date) => DateTime.parse('${date}T00:00:00Z').weekday;

  final step = interval > 0 ? interval : 1;
  final String next;
  if (type == 'weekly') {
    final weekdays = <int>{
      for (final part in (days ?? '').split(','))
        if (int.tryParse(part.trim()) case final v? when v >= 1 && v <= 7) v,
    }.toList()..sort();
    final current = isoWeekday(scheduled);
    if (weekdays.isEmpty) {
      next = addDays(scheduled, step * 7);
    } else {
      final later = weekdays.where((day) => day > current).firstOrNull;
      next = later != null
          ? addDays(scheduled, later - current)
          : addDays(scheduled, 7 - current + (step - 1) * 7 + weekdays.first);
    }
  } else {
    next = addDays(scheduled, step);
  }
  if (end != null && next.compareTo(end) > 0) return null;
  return next;
}
