// Kiểm thử "ép tràn": dựng các widget dùng chung ở nhiều cỡ màn hình, cỡ chữ
// hệ thống (1.0 / 1.5 / 2.0), sáng/tối, có/không bàn phím với nội dung dài và
// khẳng định không có lỗi "A RenderFlex overflowed by x pixels".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/dashboard.dart';
import 'package:todonote/models/habit.dart';
import 'package:todonote/models/note.dart';
import 'package:todonote/models/tag.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/screens/auth/login_screen.dart';
import 'package:todonote/screens/auth/register_screen.dart';
import 'package:todonote/screens/checklists/template_create_screen.dart';
import 'package:todonote/screens/habits/habit_create_screen.dart';
import 'package:todonote/screens/notes/note_editor_screen.dart';
import 'package:todonote/screens/settings/settings_screen.dart';
import 'package:todonote/screens/todos/todo_create_screen.dart';
import 'package:todonote/theme/app_theme.dart';
import 'package:todonote/widgets/app_list_section.dart';
import 'package:todonote/widgets/app_sheet.dart';
import 'package:todonote/widgets/app_state_views.dart';
import 'package:todonote/widgets/calendar_day_cell.dart';
import 'package:todonote/widgets/calendar_day_timeline.dart';
import 'package:todonote/widgets/checklist_paste_steps_sheet.dart';
import 'package:todonote/widgets/clamp_text_scale.dart';
import 'package:todonote/widgets/dashboard_habit_card.dart';
import 'package:todonote/widgets/duration_picker_sheet.dart';
import 'package:todonote/widgets/empty_state.dart';
import 'package:todonote/widgets/habit_card.dart';
import 'package:todonote/widgets/habit_log_sheet.dart';
import 'package:todonote/widgets/note_card.dart';
import 'package:todonote/widgets/primary_button.dart';
import 'package:todonote/widgets/todo_flag_button.dart';
import 'package:todonote/widgets/todo_tile.dart';

const _screens = <(String, Size)>[
  ('nhỏ 320x568', Size(320, 568)),
  ('thường 360x720', Size(360, 720)),
  ('ngang 640x320', Size(640, 320)),
];
const _textScales = [1.0, 1.5, 2.0];

const _longTitle =
    'Chuẩn bị tài liệu họp quý với toàn bộ phòng ban và gửi cho từng thành '
    'viên trước giờ làm việc để mọi người kịp đọc';
const _longText =
    'Mô tả rất dài để kiểm tra việc xuống dòng, cắt chữ và cuộn của từng '
    'thành phần khi cỡ chữ hệ thống bị phóng to tối đa trên màn hình nhỏ.';

/// Chạy [body] cho từng tổ hợp, gom MỌI lỗi layout (không dừng ở lỗi đầu tiên)
/// rồi báo một lần: "tệp:dòng | tổ hợp | số px tràn".
Future<void> _runCombos(
  WidgetTester tester,
  String name,
  Iterable<_Combo> combos,
  Future<void> Function(_Combo combo) body, {
  bool overflowOnly = false,
}) async {
  final failures = <String>{};
  final previous = FlutterError.onError;
  _Combo? current;
  FlutterError.onError = (details) {
    final text = details.toString();
    final amount = RegExp(
      r'overflowed by ([\d.]+) pixels on the (\w+)',
    ).firstMatch(text);
    final where = RegExp(r'lib/[\w/]+\.dart:\d+:\d+').firstMatch(text);
    // Màn hình thật có thể ném lỗi không liên quan (mạng, DB…) khi dựng trong
    // test; ở chế độ overflowOnly chỉ quan tâm lỗi tràn layout.
    if (overflowOnly && amount == null) return;
    final what =
        amount?.group(0) ?? details.exceptionAsString().split('\n').first;
    failures.add('${where?.group(0) ?? '?'} | $current | $what');
  };
  try {
    for (final combo in combos) {
      current = combo;
      // Dựng lại từ đầu: bỏ route/sheet của tổ hợp trước và tạo render object mới
      // (Flutter chỉ báo tràn một lần cho mỗi render object).
      await tester.pumpWidget(const SizedBox.shrink());
      _applyView(tester, combo);
      await body(combo);
      // Xả các lỗi còn treo trong binding để không lẫn sang tổ hợp sau.
      tester.takeException();
    }
    // Gỡ cây widget và cho các Timer 0ms còn sót (vd. thanh công cụ Quill)
    // chạy xong, tránh lỗi "Timer is still pending" khi kết thúc test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  } finally {
    FlutterError.onError = previous;
  }
  expect(failures, isEmpty, reason: '$name:\n${failures.join('\n')}');
}

/// Chạy [body] cho mọi tổ hợp (màn hình × cỡ chữ × sáng/tối).
void _stress(
  String name,
  Future<void> Function(WidgetTester tester, _Combo combo) body, {
  List<(String, Size)> screens = _screens,
}) {
  testWidgets(name, (tester) async {
    await _runCombos(tester, name, [
      for (final screen in screens)
        for (final scale in _textScales)
          for (final brightness in Brightness.values)
            _Combo(screen.$1, screen.$2, scale, brightness),
    ], (combo) => body(tester, combo));
  });
}

class _Combo {
  final String screenName;
  final Size size;
  final double textScale;
  final Brightness brightness;
  double keyboard = 0;

  _Combo(this.screenName, this.size, this.textScale, this.brightness);

  ThemeData get theme =>
      brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();

  @override
  String toString() => '$screenName, chữ x$textScale, ${brightness.name}';
}

void _applyView(WidgetTester tester, _Combo combo) {
  final view = tester.view;
  view.physicalSize = combo.size;
  view.devicePixelRatio = 1.0;
  view.viewInsets = FakeViewPadding(bottom: combo.keyboard);
  tester.platformDispatcher.textScaleFactorTestValue = combo.textScale;
  addTearDown(() {
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    view.resetViewInsets();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  _Combo combo,
  Widget home, {
  Duration settle = const Duration(milliseconds: 600),
}) async {
  await tester.pumpWidget(MaterialApp(theme: combo.theme, home: home));
  await tester.pump(settle);
}

/// Mở [open] (thường là showAppSheet) bằng nút bấm, đợi hiệu ứng xong.
Future<void> _openFromButton(
  WidgetTester tester,
  _Combo combo,
  Future<void> Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: combo.theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => open(context),
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('mở'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Todo _todo(String id, {String title = _longTitle, List<Tag> tags = const []}) {
  final now = DateTime(2026, 6, 26);
  return Todo(
    id: id,
    title: title,
    description: _longText,
    isFrog: true,
    isImportant: true,
    isUrgent: true,
    estimatedMinutes: 125,
    scheduledDate: now,
    time: '09:00',
    tags: tags,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  _stress('EmptyState trong vùng thấp', (tester, combo) async {
    await _pumpApp(
      tester,
      combo,
      const Scaffold(
        body: SizedBox(
          height: 150,
          child: EmptyState(
            title: _longTitle,
            subtitle: _longText,
            buttonLabel: 'Tạo thói quen đầu tiên của bạn',
          ),
        ),
      ),
    );
  });

  _stress('AppErrorState trong vùng thấp', (tester, combo) async {
    await _pumpApp(
      tester,
      combo,
      Scaffold(
        body: SizedBox(
          height: 150,
          child: AppErrorState(message: _longText, onRetry: () {}),
        ),
      ),
    );
  });

  _stress('Nút chính nhãn dài cạnh nhau', (tester, combo) async {
    await _pumpApp(
      tester,
      combo,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Hủy bấm giờ ngay bây giờ',
                  variant: PrimaryButtonVariant.tonal,
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  label: 'Trở lại màn hình chính',
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  });

  _stress('AppListTile nhãn / mô tả / giá trị dài', (tester, combo) async {
    await _pumpApp(
      tester,
      combo,
      Scaffold(
        body: ListView(
          children: [
            AppListSection(
              children: [
                AppListTile(
                  icon: Icons.category_rounded,
                  title: _longTitle,
                  subtitle: _longText,
                  value: 'Chưa phân loại rất dài',
                  onTap: () {},
                ),
                AppListTile(
                  icon: Icons.delete_rounded,
                  title: _longTitle,
                  destructive: true,
                  showChevron: false,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  });

  _stress('Bottom sheet nhiều dòng (AppSheetScaffold)', (tester, combo) async {
    await _openFromButton(
      tester,
      combo,
      (context) => showAppSheet<String>(
        context: context,
        builder: (ctx) => AppSheetScaffold(
          title: _longTitle,
          subtitle: _longText,
          child: AppListSection(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (var i = 0; i < 6; i++)
                AppListTile(
                  icon: Icons.check_circle_rounded,
                  title: 'Hành động số $i rất dài để thử việc xuống dòng',
                  showChevron: false,
                  onTap: () {},
                ),
            ],
          ),
        ),
      ),
    );
  });

  _stress('DurationPickerSheet', (tester, combo) async {
    await _openFromButton(
      tester,
      combo,
      (context) => showAppSheet<int>(
        context: context,
        builder: (_) => const DurationPickerSheet(),
      ),
    );
  });

  testWidgets('Sheet dán nhiều bước (bàn phím mở)', (tester) async {
    await _runCombos(
      tester,
      'dán bước',
      [
        for (final screen in _screens)
          for (final scale in _textScales)
            _Combo(screen.$1, screen.$2, scale, Brightness.light)
              ..keyboard = screen.$2.height * 0.4,
      ],
      (combo) async {
        await _openFromButton(
          tester,
          combo,
          (context) => showChecklistPasteStepsSheet(
            context,
            initialText: List.generate(
              12,
              (i) => 'Bước $i $_longText',
            ).join('\n'),
          ),
        );
      },
    );
  });

  _stress('TodoFlagButton x3', (tester, combo) async {
    await _pumpApp(
      tester,
      combo,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TodoFlagButton(
                    selected: true,
                    selectedColor: Colors.green,
                    label: 'Ếch xanh',
                    emoji: '🐸',
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TodoFlagButton(
                    selected: false,
                    selectedColor: Colors.orange,
                    label: 'Quan trọng',
                    icon: Icons.star_rounded,
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TodoFlagButton(
                    selected: true,
                    selectedColor: Colors.red,
                    label: 'Khẩn cấp',
                    icon: Icons.bolt_rounded,
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  });

  _stress('NoteCard tiêu đề / tag dài', (tester, combo) async {
    final now = DateTime(2026, 6, 26);
    final note = Note(
      id: 'n1',
      title: _longTitle,
      type: NoteType.cornell,
      body: _longText,
      isPinned: true,
      tags: const [
        Tag(
          id: 't1',
          name: 'Một thẻ tag có tên cực kỳ dài',
          color: Colors.teal,
        ),
        Tag(
          id: 't2',
          name: 'Thẻ thứ hai cũng dài không kém',
          color: Colors.pink,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await _pumpApp(
      tester,
      combo,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [NoteCard(note: note)],
        ),
      ),
    );
  });

  _stress('TodoTile đầy đủ chip + tag dài', (tester, combo) async {
    final todo = _todo(
      't1',
      tags: const [
        Tag(id: 'a', name: 'Một thẻ tag có tên cực kỳ dài', color: Colors.teal),
        Tag(id: 'b', name: 'Thẻ thứ hai', color: Colors.pink),
        Tag(id: 'c', name: 'Thẻ thứ ba', color: Colors.indigo),
      ],
    );
    await _pumpApp(
      tester,
      combo,
      Scaffold(
        body: ListView(
          children: [
            TodoTile(todo: todo),
            TodoTile(todo: todo, compact: true),
          ],
        ),
      ),
    );
  });

  _stress('Ô lưới thói quen / lịch (công thức như màn hình)', (
    tester,
    combo,
  ) async {
    final habit = Habit(
      id: 'h1',
      title: _longTitle,
      iconName: 'book',
      icon: Icons.menu_book,
      color: Colors.green,
      startDate: DateTime(2026, 6, 1),
      currentStreak: 123,
      longestStreak: 456,
    );
    await _pumpApp(
      tester,
      combo,
      Scaffold(
        body: Builder(
          builder: (context) {
            // Giống HabitsListScreen / CalendarScreen: chiều cao ô theo cỡ chữ
            // (kẹp 1.35) và nội dung ô cũng kẹp cỡ chữ.
            final scale = MediaQuery.textScalerOf(
              context,
            ).scale(1).clamp(1.0, 1.35);
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      mainAxisExtent: 150 * scale,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => ClampTextScale(
                        maxScale: 1.35,
                        child: HabitCard(habit: habit, recentCompletions: 7),
                      ),
                      childCount: 6,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 120 * scale,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => ClampTextScale(
                        maxScale: 1.35,
                        child: CalendarDayCell(
                          date: DateTime(2026, 6, 20 + i),
                          isFuture: i.isOdd,
                          isToday: i == 2,
                          score: i.isOdd ? null : 100,
                          totalTodos: 123,
                          doneTodos: 120,
                          habitsTotal: 45,
                          habitsCompleted: 44,
                        ),
                      ),
                      childCount: 6,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  });

  _stress('DashboardHabitCard x3 trong hàng (IntrinsicHeight)', (
    tester,
    combo,
  ) async {
    final habit = Habit(
      id: 'h1',
      title: _longTitle,
      iconName: 'book',
      icon: Icons.menu_book,
      color: Colors.green,
      startDate: DateTime(2026, 6, 1),
      currentStreak: 123,
      longestStreak: 456,
    );
    await _pumpApp(
      tester,
      combo,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: DashboardHabitCard(
                        habit: habit,
                        completed: i.isEven,
                        onTap: () {},
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  });

  _stress('Bảng xác nhận thói quen ở Dashboard', (tester, combo) async {
    final today = DateTime(2026, 6, 26);
    final habit = Habit(
      id: 'h1',
      title: _longTitle,
      iconName: 'book',
      icon: Icons.menu_book,
      color: Colors.green,
      startDate: DateTime(2026, 1, 1),
      currentStreak: 123,
      longestStreak: 456,
    );
    await _openFromButton(
      tester,
      combo,
      (context) => showHabitLogSheet(
        context,
        habit: habit,
        today: today,
        completedByDate: {
          for (var i = 1; i < 20; i++)
            today.subtract(Duration(days: i)): i.isEven,
        },
      ),
    );
  });

  _stress('Thanh điều hướng dưới + FAB', (tester, combo) async {
    await _pumpApp(
      tester,
      combo,
      Scaffold(
        body: const SizedBox.expand(),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add_rounded),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Hôm nay'),
            BottomNavigationBarItem(
              icon: Icon(Icons.check_circle),
              label: 'Todos',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.note), label: 'Notes'),
            BottomNavigationBarItem(
              icon: Icon(Icons.local_fire_department),
              label: 'Thói quen',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month),
              label: 'Lịch',
            ),
          ],
        ),
      ),
    );
  });

  _stress('Hộp thoại xác nhận nội dung dài', (tester, combo) async {
    await _openFromButton(
      tester,
      combo,
      (context) => showAppConfirmDialog(
        context,
        title: _longTitle,
        message: '$_longText $_longText $_longText',
        confirmLabel: 'Xóa vĩnh viễn',
        destructive: true,
      ),
    );
  });

  _stress('Timeline lịch với việc có đủ nhãn', (tester, combo) async {
    CalendarDayTodo todo(String id, int minute, {int? estimate}) {
      final hour = (minute ~/ 60).toString().padLeft(2, '0');
      final min = (minute % 60).toString().padLeft(2, '0');
      return CalendarDayTodo(
        id: id,
        title: _longTitle,
        status: 'open',
        position: minute,
        scheduledDate: null,
        time: '$hour:$min',
        minutesSinceMidnight: minute,
        estimatedMinutes: estimate,
        isFrog: true,
        isImportant: true,
        isUrgent: true,
        hasSubtasks: true,
      );
    }

    final date = DateTime(2026, 6, 26);
    final detail = CalendarDayDetail(
      date: date,
      timezone: 'Asia/Ho_Chi_Minh',
      week: CalendarWeek.fromJson(null, selectedDate: date),
      timeline: CalendarTimeline(
        startMinute: 0,
        endMinute: 1440,
        slotMinutes: 60,
        hourMarks: List.generate(
          25,
          (i) => CalendarHourMark(
            minute: i * 60,
            label: '${(i % 24).toString().padLeft(2, '0')}:00',
          ),
        ),
      ),
      currentTimeIndicator: CalendarCurrentTimeIndicator.hidden,
      timedTodos: [
        todo('a', 540),
        todo('b', 545, estimate: 15),
        todo('c', 600, estimate: 125),
        todo('d', 930),
        todo('e', 945, estimate: 5),
      ],
      untimedTodos: const [],
      totals: const CalendarDayTotals(
        totalTodos: 5,
        timedTodos: 5,
        untimedTodos: 0,
        doneTodos: 0,
      ),
    );
    await _pumpApp(
      tester,
      combo,
      Scaffold(
        body: SingleChildScrollView(
          child: CalendarDayTimeline(
            detail: detail,
            now: DateTime(2026, 6, 26, 16, 44),
          ),
        ),
      ),
    );
  });

  // --- Màn hình thật (dựng trong MaterialApp trần; mạng/DB lỗi thì bỏ qua) ---
  void stressScreen(String name, Widget Function() build) {
    testWidgets('Màn hình: $name', (tester) async {
      await _runCombos(
        tester,
        name,
        [
          for (final screen in _screens)
            for (final scale in _textScales)
              for (final keyboard in const [0.0, 0.4])
                _Combo(screen.$1, screen.$2, scale, Brightness.light)
                  ..keyboard = screen.$2.height * keyboard,
        ],
        (combo) => _pumpApp(tester, combo, build()),
        overflowOnly: true,
      );
    });
  }

  stressScreen('TodoCreateScreen', () => const TodoCreateScreen());
  stressScreen('HabitCreateScreen', () => const HabitCreateScreen());
  stressScreen('TemplateCreateScreen', () => const TemplateCreateScreen());
  stressScreen('LoginScreen', () => const LoginScreen());
  stressScreen('RegisterScreen', () => const RegisterScreen());
  stressScreen('SettingsScreen', () => const SettingsScreen());
  stressScreen(
    'NoteEditorScreen (free)',
    () => const NoteEditorScreen(initialType: NoteType.free),
  );
  stressScreen(
    'NoteEditorScreen (cornell)',
    () => const NoteEditorScreen(initialType: NoteType.cornell),
  );
}
