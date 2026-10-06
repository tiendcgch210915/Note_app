import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/theme/app_colors.dart';
import 'package:todonote/widgets/todo_timed_title.dart';

void main() {
  testWidgets('only the bracketed time receives the status color', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoTimedTitle(
            title: 'Đi tập GYM',
            time: '15:51',
            scheduledDate: DateTime(2026, 6, 26),
            now: DateTime(2026, 6, 26, 14, 50),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));
    final root = richText.text as TextSpan;
    final timeSpan = root.children![0] as TextSpan;
    final titleSpan = root.children![2] as TextSpan;

    expect(timeSpan.text, '[15:51]');
    expect(timeSpan.style?.color, AppColors.success);
    expect(titleSpan.text, 'Đi tập GYM');
    expect(titleSpan.style, isNull);
  });

  testWidgets('near and overdue times use warning and danger colors', (
    tester,
  ) async {
    Future<Color?> renderColor(String time) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodoTimedTitle(
              title: 'Todo',
              time: time,
              scheduledDate: DateTime(2026, 6, 26),
              now: DateTime(2026, 6, 26, 14, 50),
            ),
          ),
        ),
      );
      final richText = tester.widget<RichText>(find.byType(RichText));
      final root = richText.text as TextSpan;
      return (root.children![0] as TextSpan).style?.color;
    }

    expect(await renderColor('15:50'), AppColors.warning);
    expect(await renderColor('13:49'), AppColors.danger);
  });
}
