import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/dashboard.dart';
import 'package:todonote/widgets/eisenhower_grid.dart';

void main() {
  testWidgets('EisenhowerGrid always renders four fixed quadrants', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EisenhowerGrid(counts: {}, previews: {}),
        ),
      ),
    );

    expect(find.byType(InkWell), findsNWidgets(4));
    expect(find.text('Quan trọng & Khẩn'), findsOneWidget);
    expect(find.text('Quan trọng - Không khẩn'), findsOneWidget);
    expect(find.text('Khẩn - Không quan trọng'), findsOneWidget);
    expect(find.text('Không q.trọng - Không khẩn'), findsOneWidget);
  });

  testWidgets('EisenhowerGrid ignores unexpected count and preview keys', (
    tester,
  ) async {
    const ignoredTodo = DashboardEisenhowerTodo(
      id: 'ignored',
      title: 'Ignored legacy bucket',
      status: 'open',
      scheduledDate: null,
      isImportant: false,
      isUrgent: false,
      isFrog: false,
      frogDate: null,
      quadrant: 'q4',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EisenhowerGrid(
            counts: {'q1': 1, 'unclassified': 99},
            previews: {
              'unclassified': [ignoredTodo],
            },
          ),
        ),
      ),
    );

    expect(find.byType(InkWell), findsNWidgets(4));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('99'), findsNothing);
    expect(find.textContaining('Ignored legacy bucket'), findsNothing);
  });
}
