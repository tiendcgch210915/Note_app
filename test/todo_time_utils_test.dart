import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/utils/todo_time_utils.dart';

void main() {
  test('todo times sort ascending with missing values last', () {
    final times = <String?>[null, '15:00', '09:00', '12:00'];

    times.sort(compareTodoTimes);

    expect(times, ['09:00', '12:00', '15:00', null]);
  });

  test('todo title displays a user-friendly time prefix', () {
    expect(todoTitleWithTime('Đi tập GYM', '09:00'), '[09:00] Đi tập GYM');
    expect(todoTitleWithTime('Viết CV', null), 'Viết CV');
  });

  test('invalid or empty times do not sort above valid times', () {
    final times = <String?>['invalid', '', '08:30'];

    times.sort(compareTodoTimes);

    expect(times.first, '08:30');
  });

  test('todo time state uses an inclusive one-hour near window', () {
    final now = DateTime(2026, 6, 26, 14, 50);
    final date = DateTime(2026, 6, 26);

    expect(
      todoTimeState(scheduledDate: date, time: '13:49', now: now),
      TodoTimeState.overdue,
    );
    expect(
      todoTimeState(scheduledDate: date, time: '13:50', now: now),
      TodoTimeState.near,
    );
    expect(
      todoTimeState(scheduledDate: date, time: '15:50', now: now),
      TodoTimeState.near,
    );
    expect(
      todoTimeState(scheduledDate: date, time: '15:51', now: now),
      TodoTimeState.upcoming,
    );
  });

  test('todo time state includes scheduled date', () {
    final now = DateTime(2026, 6, 26, 14, 50);

    expect(
      todoTimeState(
        scheduledDate: DateTime(2026, 6, 25),
        time: '23:00',
        now: now,
      ),
      TodoTimeState.overdue,
    );
    expect(
      todoTimeState(
        scheduledDate: DateTime(2026, 6, 27),
        time: '08:00',
        now: now,
      ),
      TodoTimeState.upcoming,
    );
  });
}
