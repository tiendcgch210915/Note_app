import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/widgets/todo_swipe_actions.dart';

void main() {
  testWidgets('TodoSwipeActions exposes date time and delete actions', (
    tester,
  ) async {
    var dateTapped = 0;
    var timeTapped = 0;
    var deleteTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoSwipeActions(
            onPickDate: () => dateTapped++,
            onPickTime: () => timeTapped++,
            onDelete: () => deleteTapped++,
            child: const SizedBox(
              height: 72,
              child: Center(child: Text('Todo row')),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('Todo row'), const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Đổi ngày'), findsOneWidget);
    expect(find.byTooltip('Đổi giờ'), findsOneWidget);
    expect(find.byTooltip('Xóa todo'), findsOneWidget);

    await tester.tap(find.byTooltip('Đổi giờ'));
    await tester.pumpAndSettle();

    expect(dateTapped, 0);
    expect(timeTapped, 1);
    expect(deleteTapped, 0);
  });

  testWidgets('opening another row closes the previous swipe actions', (
    tester,
  ) async {
    var firstDateTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TodoSwipeActions(
                onPickDate: () => firstDateTapped++,
                onPickTime: () {},
                onDelete: () {},
                child: const SizedBox(
                  height: 72,
                  child: Center(child: Text('Todo row A')),
                ),
              ),
              TodoSwipeActions(
                onPickDate: () {},
                onPickTime: () {},
                onDelete: () {},
                child: const SizedBox(
                  height: 72,
                  child: Center(child: Text('Todo row B')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.drag(find.text('Todo row A'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    final firstOpenCenter = tester.getCenter(find.text('Todo row A'));
    await tester.drag(find.text('Todo row B'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    final firstAfterSecondOpenCenter = tester.getCenter(
      find.text('Todo row A'),
    );

    expect(firstAfterSecondOpenCenter.dx, greaterThan(firstOpenCenter.dx + 50));
    expect(firstDateTapped, 0);
  });

  testWidgets('right swipe exposes time and edit actions only', (tester) async {
    var timeTapped = 0;
    var editTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoSwipeActions(
            direction: TodoSwipeDirection.right,
            onPickTime: () => timeTapped++,
            onEdit: () => editTapped++,
            child: const SizedBox(
              height: 72,
              child: Center(child: Text('Calendar todo row')),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('Calendar todo row'), const Offset(140, 0));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Đổi giờ'), findsOneWidget);
    expect(find.byTooltip('Chỉnh sửa'), findsOneWidget);
    expect(find.byTooltip('Đổi ngày'), findsNothing);
    expect(find.byTooltip('Xóa todo'), findsNothing);

    await tester.tap(find.byTooltip('Chỉnh sửa'));
    await tester.pumpAndSettle();

    expect(timeTapped, 0);
    expect(editTapped, 1);
  });

  testWidgets('calendar swipe actions can stay pinned to the row top', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoSwipeActions(
            direction: TodoSwipeDirection.right,
            actionAlignment: TodoSwipeActionAlignment.top,
            onPickTime: () {},
            onEdit: () {},
            child: const SizedBox(
              key: ValueKey('tall-calendar-row'),
              height: 220,
              child: Center(child: Text('Tall calendar todo row')),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.text('Tall calendar todo row'),
      const Offset(140, 0),
    );
    await tester.pumpAndSettle();

    final rowTop = tester
        .getTopLeft(find.byKey(const ValueKey('tall-calendar-row')))
        .dy;
    final actionTop = tester.getTopLeft(find.byTooltip('Đổi giờ')).dy;

    expect(actionTop, lessThan(rowTop + 40));
  });
}
