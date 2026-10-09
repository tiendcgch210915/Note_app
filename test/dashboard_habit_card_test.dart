import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/habit.dart';
import 'package:todonote/widgets/dashboard_habit_card.dart';

void main() {
  testWidgets('DashboardHabitCard shows current and longest streak', (
    tester,
  ) async {
    var toggled = false;
    final habit = Habit(
      id: 'habit-1',
      title: 'Đọc sách',
      iconName: 'book',
      icon: Icons.menu_book,
      color: Colors.green,
      startDate: DateTime(2026, 6, 1),
      currentStreak: 12,
      longestStreak: 30,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 140,
              child: DashboardHabitCard(
                habit: habit,
                completed: false,
                onTap: () => toggled = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Đọc sách'), findsOneWidget);
    expect(find.text('12 ngày'), findsOneWidget);
    expect(find.text('Kỷ lục: 30 ngày'), findsOneWidget);

    await tester.tap(find.byType(DashboardHabitCard));

    expect(toggled, isTrue);
  });
}
