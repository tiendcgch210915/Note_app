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

  testWidgets('EisenhowerGrid sorts previews by time and prefixes titles', (
    tester,
  ) async {
    DashboardEisenhowerTodo todo(String id, String title, String? time) {
      return DashboardEisenhowerTodo(
        id: id,
        title: title,
        status: 'open',
        scheduledDate: DateTime(2026, 6, 26),
        time: time,
        isImportant: true,
        isUrgent: true,
        isFrog: false,
        frogDate: null,
        quadrant: 'q1',
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EisenhowerGrid(
            counts: const {'q1': 4},
            previews: {
              'q1': [
                todo('cv', 'Viết CV', '15:00'),
                todo('none', 'Không đặt giờ', null),
                todo('gym', 'Đi tập GYM', '09:00'),
                todo('english', 'Học tiếng Anh', '12:00'),
              ],
            },
          ),
        ),
      ),
    );

    final gym = find.text('· [09:00] Đi tập GYM', findRichText: true);
    final english = find.text('· [12:00] Học tiếng Anh', findRichText: true);
    final cv = find.text('· [15:00] Viết CV', findRichText: true);
    final noTime = find.text('· Không đặt giờ');

    expect(gym, findsOneWidget);
    expect(english, findsOneWidget);
    expect(cv, findsOneWidget);
    expect(noTime, findsOneWidget);
    expect(tester.getTopLeft(gym).dy, lessThan(tester.getTopLeft(english).dy));
    expect(tester.getTopLeft(english).dy, lessThan(tester.getTopLeft(cv).dy));
    expect(tester.getTopLeft(cv).dy, lessThan(tester.getTopLeft(noTime).dy));
  });
}
