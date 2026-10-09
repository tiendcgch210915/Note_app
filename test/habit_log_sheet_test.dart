import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/habit.dart';
import 'package:todonote/theme/app_theme.dart';
import 'package:todonote/utils/date_utils.dart';
import 'package:todonote/widgets/habit_calendar_grid.dart';
import 'package:todonote/widgets/habit_log_sheet.dart';
import 'package:todonote/widgets/habit_today_log_panel.dart';

final _today = AppDateUtils.dateOnly(DateTime.now());

Habit _habit({DateTime? startDate}) => Habit(
  id: 'h1',
  title: 'Đọc sách',
  iconName: 'book',
  icon: Icons.menu_book,
  color: Colors.green,
  startDate: startDate ?? _today.subtract(const Duration(days: 100)),
  currentStreak: 3,
  longestStreak: 9,
);

/// Dựng màn hình có nút "mở"; kết quả của sheet được ghi vào [result].
Future<void> _openSheet(
  WidgetTester tester, {
  required Map<DateTime, bool> completedByDate,
  required List<bool?> result,
  Habit? habit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result.add(
                  await showHabitLogSheet(
                    context,
                    habit: habit ?? _habit(),
                    completedByDate: completedByDate,
                    today: _today,
                  ),
                );
              },
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('mở'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hiện lịch 28 ngày, câu hỏi và hai nút nhưng chưa ghi log', (
    tester,
  ) async {
    final result = <bool?>[];
    await _openSheet(tester, completedByDate: const {}, result: result);

    expect(find.byType(HabitCalendarGrid), findsOneWidget);
    expect(find.text('Đọc sách'), findsOneWidget);
    expect(find.text('Đã hoàn thành hôm nay chưa?'), findsOneWidget);
    expect(find.text('Hoàn thành'), findsOneWidget);
    expect(find.text('Bỏ lỡ'), findsOneWidget);
    // Không có nhãn "28 ngày gần đây" như trang chi tiết.
    expect(find.textContaining('28 ngày'), findsNothing);
    // Chỉ mở bảng, chưa chọn gì => chưa có kết quả.
    expect(result, isEmpty);
  });

  testWidgets('lịch có đúng 28 ô ngày và ô hôm nay nằm trong đó', (
    tester,
  ) async {
    await _openSheet(tester, completedByDate: const {}, result: []);

    // Mỗi ô hiển thị "ngày/tháng" (vd. 8/10).
    final label = RegExp(r'^\d{1,2}/\d{1,2}$');
    final dayLabels = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => label.hasMatch(t.data ?? ''))
        .toList();
    expect(dayLabels, hasLength(28));
    expect(find.text('${_today.day}/${_today.month}'), findsOneWidget);
  });

  testWidgets('bảng chỉ chiếm một phần màn hình, không phủ kín', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _openSheet(tester, completedByDate: const {}, result: []);

    final sheetHeight = tester.getSize(find.byType(BottomSheet)).height;
    expect(sheetHeight, lessThan(900 * 0.85));
    // Màn hình phía sau vẫn còn nhìn thấy (nút "mở" nằm sau scrim).
    expect(find.text('mở'), findsOneWidget);
  });

  testWidgets('lịch chỉ để xem: nhấn giữ một ngày không mở thêm gì', (
    tester,
  ) async {
    await _openSheet(tester, completedByDate: const {}, result: []);

    final grid = tester.widget<HabitCalendarGrid>(
      find.byType(HabitCalendarGrid),
    );
    expect(grid.onLongPress, isNull);

    await tester.longPress(find.text('${_today.day}/${_today.month}'));
    await tester.pumpAndSettle();
    // Vẫn chỉ có một bottom sheet (không có menu sửa log).
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Xóa log'), findsNothing);
    expect(find.text('Đánh dấu chưa làm'), findsNothing);
  });

  testWidgets('bấm "Hoàn thành" trả về true và đóng bảng', (tester) async {
    final result = <bool?>[];
    await _openSheet(tester, completedByDate: const {}, result: result);

    await tester.tap(find.text('Hoàn thành'));
    await tester.pumpAndSettle();

    expect(result, [true]);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('bấm "Bỏ lỡ" trả về false và đóng bảng', (tester) async {
    final result = <bool?>[];
    await _openSheet(tester, completedByDate: const {}, result: result);

    await tester.tap(find.text('Bỏ lỡ'));
    await tester.pumpAndSettle();

    expect(result, [false]);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('đóng bảng bằng cách chạm ra ngoài trả về null (không ghi log)', (
    tester,
  ) async {
    final result = <bool?>[];
    await _openSheet(tester, completedByDate: const {}, result: result);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, [null]);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('lịch tô trạng thái các ngày đã ghi nhận', (tester) async {
    final yesterday = _today.subtract(const Duration(days: 1));
    final twoDaysAgo = _today.subtract(const Duration(days: 2));
    await _openSheet(
      tester,
      completedByDate: {yesterday: true, twoDaysAgo: false},
      result: [],
    );

    // Ô đã ghi nhận có biểu tượng lửa (CustomPaint), ô chưa ghi nhận thì không.
    Finder flameIn(DateTime d) => find.descendant(
      of: find
          .ancestor(
            of: find.text('${d.day}/${d.month}'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
      matching: find.byType(CustomPaint),
    );
    expect(flameIn(yesterday), findsWidgets);
    expect(flameIn(twoDaysAgo), findsWidgets);
    final threeDaysAgo = _today.subtract(const Duration(days: 3));
    expect(flameIn(threeDaysAgo), findsNothing);
  });

  testWidgets('HabitTodayLogPanel đổi câu hỏi theo trạng thái đã ghi nhận', (
    tester,
  ) async {
    Future<void> pumpPanel(bool? completed) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: HabitTodayLogPanel(completed: completed, onLog: (_) {}),
        ),
      ),
    );

    await pumpPanel(null);
    expect(find.text('Đã hoàn thành hôm nay chưa?'), findsOneWidget);
    await pumpPanel(true);
    expect(find.text('Bạn đã hoàn thành hôm nay'), findsOneWidget);
    await pumpPanel(false);
    expect(find.text('Bạn đã đánh dấu bỏ lỡ hôm nay'), findsOneWidget);
  });
}
