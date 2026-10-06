import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/widgets/calendar_day_cell.dart';
import 'package:todonote/widgets/score_ring.dart';

void main() {
  testWidgets('ScoreRing displays score above 100 against target 100', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: ScoreRing(score: 115))),
      ),
    );

    expect(find.text('115'), findsOneWidget);
    expect(find.text('/100'), findsOneWidget);
  });

  testWidgets('CalendarDayCell does not clamp score above 100', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarDayCell(
            date: DateTime(2026, 6, 16),
            isFuture: false,
            score: 115,
            totalTodos: 5,
            doneTodos: 4,
            habitsTotal: 2,
            habitsCompleted: 2,
          ),
        ),
      ),
    );

    expect(find.text('115'), findsOneWidget);
    expect(find.text('100'), findsNothing);
    expect(find.text('4/5 todos'), findsOneWidget);
    expect(find.text('2/2 habits'), findsOneWidget);
  });

  testWidgets('CalendarDayCell highlights days that reach 100 points', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarDayCell(
            date: DateTime(2026, 6, 16),
            isFuture: false,
            score: 100,
            totalTodos: 5,
            doneTodos: 5,
            habitsTotal: 2,
            habitsCompleted: 2,
          ),
        ),
      ),
    );

    expect(find.text('100'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-fire-score-badge')), findsOne);
    expect(find.byKey(const ValueKey('calendar-fire-score-icon')), findsOne);
    expect(find.byKey(const ValueKey('calendar-fire-streak-chip')), findsOne);
  });

  testWidgets('CalendarDayCell suppresses fire score before todo gate passes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarDayCell(
            date: DateTime(2026, 7, 3),
            isFuture: false,
            score: 105,
            totalTodos: 1,
            doneTodos: 1,
            habitsTotal: 6,
            habitsCompleted: 6,
          ),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);
    expect(find.text('105'), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-fire-score-badge')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('calendar-fire-score-icon')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('calendar-fire-streak-chip')),
      findsNothing,
    );
  });
}
