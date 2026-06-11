import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/habit_log.dart';
import '../models/note.dart';
import '../models/run.dart';
import '../models/run_item.dart';
import '../models/tag.dart';
import '../models/template.dart';
import '../models/template_item.dart';
import '../models/todo.dart';
import '../models/user.dart';
import '../theme/app_colors.dart';

/// Snapshot dashboard hôm nay.
class DashboardSnapshot {
  final int score;
  final Map<String, int> eisenhowerCounts;
  final int habitsToday;
  final int habitsCompleted;
  final Todo? frog;

  const DashboardSnapshot({
    required this.score,
    required this.eisenhowerCounts,
    required this.habitsToday,
    required this.habitsCompleted,
    required this.frog,
  });
}

/// Tất cả dữ liệu giả cho UI scaffold. Mọi ngày tham chiếu qua [today].
class MockData {
  MockData._();

  /// Anchor day — date-only (00:00). Toàn bộ data tham chiếu đến mốc này.
  static DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _daysAgo(int n) => today().subtract(Duration(days: n));
  static DateTime _daysAhead(int n) => today().add(Duration(days: n));

  // ─── User ─────────────────────────────────────────────────────────
  static const User currentUser = User(
    id: 'u1',
    email: 'demo@local',
    displayName: 'Trần Demo',
    timezone: 'Asia/Ho_Chi_Minh',
  );

  // ─── Tags ─────────────────────────────────────────────────────────
  static const List<Tag> tags = [
    Tag(id: 't1', name: 'work', color: AppColors.tagIndigo),
    Tag(id: 't2', name: 'personal', color: AppColors.tagGreen),
    Tag(id: 't3', name: 'study', color: AppColors.tagAmber),
    Tag(id: 't4', name: 'urgent', color: AppColors.tagRed),
  ];

  static Tag tagById(String id) =>
      tags.firstWhere((t) => t.id == id, orElse: () => tags.first);

  // ─── Todos ────────────────────────────────────────────────────────
  static List<Todo> todos = _buildTodos();

  static List<Todo> _buildTodos() {
    final now = today();
    return [
      Todo(
        id: 'todo1',
        title: 'Viết báo cáo Q2',
        description: 'Tổng hợp số liệu doanh thu, so sánh với Q1, vẽ chart.',
        status: TodoStatus.open,
        position: 1,
        isFrog: true,
        frogDate: now,
        isImportant: true,
        isUrgent: true,
        estimatedMinutes: 90,
        scheduledDate: now,
        dueAt: now.add(const Duration(hours: 17)),
        tagIds: const ['t1', 't4'],
        createdAt: _daysAgo(2),
        updatedAt: _daysAgo(1),
      ),
      Todo(
        id: 'todo2',
        title: 'Phản hồi email khách hàng',
        description: '5 email pending từ hôm qua.',
        status: TodoStatus.inProgress,
        position: 2,
        isImportant: true,
        isUrgent: true,
        estimatedMinutes: 25,
        scheduledDate: now,
        tagIds: const ['t1'],
        createdAt: _daysAgo(1),
        updatedAt: now,
      ),
      Todo(
        id: 'todo3',
        title: 'Đọc chương 3 sách Atomic Habits',
        status: TodoStatus.open,
        position: 3,
        isImportant: true,
        isUrgent: false,
        estimatedMinutes: 45,
        scheduledDate: now,
        tagIds: const ['t3'],
        createdAt: _daysAgo(3),
        updatedAt: _daysAgo(1),
      ),
      Todo(
        id: 'todo4',
        title: 'Họp daily standup',
        status: TodoStatus.done,
        position: 4,
        isImportant: false,
        isUrgent: true,
        estimatedMinutes: 15,
        scheduledDate: now,
        completedAt: now.add(const Duration(hours: 9, minutes: 30)),
        tagIds: const ['t1'],
        createdAt: now,
        updatedAt: now,
      ),
      Todo(
        id: 'todo5',
        title: 'Xem 1 tập phim',
        status: TodoStatus.open,
        position: 5,
        isImportant: false,
        isUrgent: false,
        estimatedMinutes: 45,
        scheduledDate: now,
        tagIds: const ['t2'],
        createdAt: now,
        updatedAt: now,
      ),
      Todo(
        id: 'todo6',
        title: 'Nghĩ tên dự án mới',
        scheduledDate: now,
        createdAt: now,
        updatedAt: now,
      ),
      // Subtasks của todo1
      Todo(
        id: 'todo1-1',
        parentId: 'todo1',
        title: 'Thu thập số liệu từ Google Analytics',
        status: TodoStatus.done,
        position: 1,
        scheduledDate: now,
        completedAt: _daysAgo(0),
        createdAt: _daysAgo(2),
        updatedAt: now,
      ),
      Todo(
        id: 'todo1-2',
        parentId: 'todo1',
        title: 'Vẽ chart so sánh Q1 vs Q2',
        status: TodoStatus.open,
        position: 2,
        scheduledDate: now,
        createdAt: _daysAgo(2),
        updatedAt: _daysAgo(1),
      ),
      // Tương lai
      Todo(
        id: 'todo7',
        title: 'Gặp mentor lúc 10h',
        isImportant: true,
        isUrgent: false,
        scheduledDate: _daysAhead(1),
        dueAt: _daysAhead(1).add(const Duration(hours: 10)),
        tagIds: const ['t2'],
        createdAt: _daysAgo(1),
        updatedAt: _daysAgo(1),
      ),
      Todo(
        id: 'todo8',
        title: 'Mua sticker laptop',
        scheduledDate: _daysAhead(1),
        createdAt: _daysAgo(1),
        updatedAt: _daysAgo(1),
      ),
      // Quá khứ
      Todo(
        id: 'todo9',
        title: 'Đi siêu thị',
        status: TodoStatus.done,
        isImportant: false,
        isUrgent: true,
        scheduledDate: _daysAgo(1),
        completedAt: _daysAgo(1).add(const Duration(hours: 18)),
        createdAt: _daysAgo(2),
        updatedAt: _daysAgo(1),
      ),
    ];
  }

  static Todo? todoById(String id) {
    for (final t in todos) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ─── Notes ────────────────────────────────────────────────────────
  static List<Note> notes = _buildNotes();

  static List<Note> _buildNotes() {
    return [
      Note(
        id: 'note1',
        title: 'Ý tưởng app productivity',
        type: NoteType.free,
        body:
            'Kết hợp 4 module: Todo, Note, Habit và Checklist trong cùng 1 app. '
            'Điểm nhấn: Eisenhower matrix cho Todo, Cornell cho Note, streak cho Habit, '
            'và template-based Checklist để chuẩn hóa các workflow lặp lại. '
            'Mỗi ngày tính điểm 0-100 dựa trên tỷ lệ hoàn thành.',
        isPinned: true,
        tags: const [
          Tag(id: 't1', name: 'work', color: AppColors.tagIndigo),
          Tag(id: 't3', name: 'study', color: AppColors.tagAmber),
        ],
        createdAt: _daysAgo(5),
        updatedAt: _daysAgo(1),
      ),
      Note(
        id: 'note2',
        title: 'Lecture: Deep Work — Cal Newport',
        type: NoteType.cornell,
        cornellCue: 'Deep work là gì?\nLợi ích?\nCách rèn luyện?',
        body:
            '- Deep work: làm việc tập trung sâu, không bị ngắt quãng.\n'
            '- Lợi ích: tăng output, học nhanh, kỹ năng vững.\n'
            '- 4 chiến lược: Monastic, Bimodal, Rhythmic, Journalistic.\n'
            '- Quy tắc: lịch cố định + môi trường không phân tâm.',
        cornellSummary:
            'Deep work là kỹ năng làm việc tập trung sâu để tạo ra giá trị cao. '
            'Cần luyện tập như cơ bắp — đặt khung giờ cố định, cắt distraction.',
        tags: const [Tag(id: 't3', name: 'study', color: AppColors.tagAmber)],
        createdAt: _daysAgo(3),
        updatedAt: _daysAgo(2),
      ),
      Note(
        id: 'note3',
        title: 'Shopping list',
        type: NoteType.free,
        body: '- Sữa tươi\n- Bánh mì\n- Trứng gà\n- Rau xà lách',
        tags: const [
          Tag(id: 't2', name: 'personal', color: AppColors.tagGreen),
        ],
        createdAt: _daysAgo(1),
        updatedAt: _daysAgo(0),
      ),
    ];
  }

  // ─── Habits ───────────────────────────────────────────────────────
  static List<Habit> habits = _buildHabits();
  static List<HabitLog> habitLogs = _buildHabitLogs();

  static List<Habit> _buildHabits() {
    return [
      Habit(
        id: 'habit1',
        title: 'Đọc sách 10 phút',
        description: '10 phút mỗi ngày, bất cứ thể loại gì.',
        icon: Icons.menu_book,
        color: const Color(0xFF4CAF50),
        frequencyType: FrequencyType.daily,
        targetPerPeriod: 1,
        startDate: _daysAgo(30),
        currentStreak: 12,
        longestStreak: 18,
      ),
      Habit(
        id: 'habit2',
        title: 'Tập thể dục',
        description: '3 buổi/tuần, ít nhất 30 phút.',
        icon: Icons.fitness_center,
        color: const Color(0xFFEF4444),
        frequencyType: FrequencyType.weekly,
        targetPerPeriod: 3,
        activeWeekdays: const [1, 3, 5],
        startDate: _daysAgo(60),
        currentStreak: 4,
        longestStreak: 20,
      ),
      Habit(
        id: 'habit3',
        title: 'Uống 2L nước',
        icon: Icons.local_drink,
        color: const Color(0xFF3B82F6),
        frequencyType: FrequencyType.daily,
        startDate: _daysAgo(14),
        currentStreak: 0,
        longestStreak: 5,
      ),
    ];
  }

  static List<HabitLog> _buildHabitLogs() {
    final logs = <HabitLog>[];
    // 14 ngày qua cho mỗi habit
    for (final habit in _buildHabits()) {
      for (var i = 0; i < 14; i++) {
        final date = _daysAgo(i);
        // Mix completed — habit1 ổn định, habit2 thưa, habit3 thất thường.
        bool completed;
        switch (habit.id) {
          case 'habit1':
            completed = i % 7 != 5; // 6/7 ngày
            break;
          case 'habit2':
            completed = i % 2 == 0; // xen kẽ
            break;
          case 'habit3':
            completed = i % 3 != 0;
            break;
          default:
            completed = false;
        }
        logs.add(
          HabitLog(
            id: '${habit.id}-log-$i',
            habitId: habit.id,
            logDate: date,
            completed: completed,
            note: (i == 0 && habit.id == 'habit1') ? 'Đọc chương 3' : null,
          ),
        );
      }
    }
    return logs;
  }

  static List<HabitLog> logsForHabit(String habitId) =>
      habitLogs.where((l) => l.habitId == habitId).toList();

  // ─── Templates + Items ────────────────────────────────────────────
  static List<Template> templates = _buildTemplates();
  static List<TemplateItem> templateItems = _buildTemplateItems();

  static List<Template> _buildTemplates() {
    return [
      Template(
        id: 'tpl1',
        title: 'Morning Routine',
        description: 'Khởi đầu ngày mới năng lượng.',
        icon: 'sun',
        category: 'Cá nhân',
        isSystem: true,
        timesUsed: 12,
        lastUsedAt: _daysAgo(1),
        createdAt: _daysAgo(30),
        updatedAt: _daysAgo(1),
      ),
      Template(
        id: 'tpl2',
        title: 'Pre-flight code review',
        description: 'Checklist trước khi merge PR.',
        icon: 'code',
        category: 'Công việc',
        isSystem: false,
        timesUsed: 5,
        lastUsedAt: _daysAgo(3),
        createdAt: _daysAgo(20),
        updatedAt: _daysAgo(3),
      ),
    ];
  }

  static List<TemplateItem> _buildTemplateItems() {
    return const [
      TemplateItem(
        id: 'ti1',
        templateId: 'tpl1',
        position: 1,
        title: 'Uống 1 ly nước',
        isRequired: true,
      ),
      TemplateItem(
        id: 'ti2',
        templateId: 'tpl1',
        position: 2,
        title: 'Tập 5 phút stretching',
        isRequired: true,
      ),
      TemplateItem(
        id: 'ti3',
        templateId: 'tpl1',
        position: 3,
        title: 'Viết 3 ưu tiên hôm nay',
        isRequired: true,
      ),
      TemplateItem(
        id: 'ti4',
        templateId: 'tpl1',
        position: 4,
        title: 'Đọc 5 phút',
        isRequired: false,
      ),
      TemplateItem(
        id: 'ti5',
        templateId: 'tpl2',
        position: 1,
        title: 'Pull main mới nhất',
        isRequired: true,
      ),
      TemplateItem(
        id: 'ti6',
        templateId: 'tpl2',
        position: 2,
        title: 'Chạy lint + format',
        isRequired: true,
      ),
      TemplateItem(
        id: 'ti7',
        templateId: 'tpl2',
        position: 3,
        title: 'Chạy unit test',
        isRequired: true,
      ),
      TemplateItem(
        id: 'ti8',
        templateId: 'tpl2',
        position: 4,
        title: 'Đọc lại diff lần cuối',
        isRequired: true,
      ),
      TemplateItem(
        id: 'ti9',
        templateId: 'tpl2',
        position: 5,
        title: 'Viết description PR rõ ràng',
        isRequired: false,
      ),
    ];
  }

  static Template? templateById(String id) {
    for (final t in templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  static List<TemplateItem> itemsForTemplate(String templateId) {
    final items = templateItems
        .where((i) => i.templateId == templateId)
        .toList();
    items.sort((a, b) => a.position.compareTo(b.position));
    return items;
  }

  // ─── Runs + RunItems ──────────────────────────────────────────────
  static List<Run> runs = _buildRuns();
  static List<RunItem> runItems = _buildRunItems();

  static List<Run> _buildRuns() {
    final now = today();
    return [
      Run(
        id: 'run1',
        templateId: 'tpl1',
        name: 'Morning Routine — Hôm nay',
        status: RunStatus.inProgress,
        startedAt: now.add(const Duration(hours: 7)),
      ),
      Run(
        id: 'run2',
        templateId: 'tpl2',
        name: 'PR #142 review',
        status: RunStatus.completed,
        startedAt: _daysAgo(3),
        completedAt: _daysAgo(3).add(const Duration(hours: 14, minutes: 30)),
      ),
    ];
  }

  static List<RunItem> _buildRunItems() {
    final now = today();
    return [
      // run1: 2/4 done
      RunItem(
        id: 'ri1',
        runId: 'run1',
        templateItemId: 'ti1',
        status: RunItemStatus.done,
        title: 'Uống 1 ly nước',
        position: 1,
        completedAt: now.add(const Duration(hours: 7, minutes: 5)),
      ),
      RunItem(
        id: 'ri2',
        runId: 'run1',
        templateItemId: 'ti2',
        status: RunItemStatus.done,
        title: 'Tập 5 phút stretching',
        position: 2,
        completedAt: now.add(const Duration(hours: 7, minutes: 15)),
      ),
      RunItem(
        id: 'ri3',
        runId: 'run1',
        templateItemId: 'ti3',
        status: RunItemStatus.pending,
        title: 'Viết 3 ưu tiên hôm nay',
        position: 3,
      ),
      RunItem(
        id: 'ri4',
        runId: 'run1',
        templateItemId: 'ti4',
        status: RunItemStatus.pending,
        title: 'Đọc 5 phút',
        isRequired: false,
        position: 4,
      ),
      // run2: hoàn thành
      RunItem(
        id: 'ri5',
        runId: 'run2',
        templateItemId: 'ti5',
        status: RunItemStatus.done,
        title: 'Pull main mới nhất',
        position: 1,
      ),
      RunItem(
        id: 'ri6',
        runId: 'run2',
        templateItemId: 'ti6',
        status: RunItemStatus.done,
        title: 'Chạy lint + format',
        position: 2,
      ),
      RunItem(
        id: 'ri7',
        runId: 'run2',
        templateItemId: 'ti7',
        status: RunItemStatus.done,
        title: 'Chạy unit test',
        position: 3,
      ),
      RunItem(
        id: 'ri8',
        runId: 'run2',
        templateItemId: 'ti8',
        status: RunItemStatus.done,
        title: 'Đọc lại diff lần cuối',
        position: 4,
      ),
      RunItem(
        id: 'ri9',
        runId: 'run2',
        templateItemId: 'ti9',
        status: RunItemStatus.skipped,
        title: 'Viết description PR rõ ràng',
        isRequired: false,
        position: 5,
      ),
    ];
  }

  static Run? runById(String id) {
    for (final r in runs) {
      if (r.id == id) return r;
    }
    return null;
  }

  static List<RunItem> itemsForRun(String runId) {
    final items = runItems.where((i) => i.runId == runId).toList();
    items.sort((a, b) => a.position.compareTo(b.position));
    return items;
  }

  // ─── Dashboard snapshot ───────────────────────────────────────────
  static DashboardSnapshot dashboardToday() {
    final todayTodos = todos
        .where(
          (t) =>
              t.parentId == null &&
              t.scheduledDate != null &&
              _isSameDay(t.scheduledDate!, today()),
        )
        .toList();

    int q1 = 0, q2 = 0, q3 = 0, q4 = 0;
    for (final t in todayTodos) {
      if (t.isImportant == true && t.isUrgent == true) {
        q1++;
      } else if (t.isImportant == true && t.isUrgent == false) {
        q2++;
      } else if (t.isImportant == false && t.isUrgent == true) {
        q3++;
      } else {
        q4++;
      }
    }

    return DashboardSnapshot(
      score: 42,
      eisenhowerCounts: {'q1': q1, 'q2': q2, 'q3': q3, 'q4': q4},
      habitsToday: 3,
      habitsCompleted: 1,
      frog: todoById('todo1'),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Score giả cho 1 ngày quá khứ — deterministic theo day-of-year.
  static int scoreForDate(DateTime date) {
    final doy = date.difference(DateTime(date.year)).inDays;
    return 35 + (doy * 7 % 60); // 35..94
  }

  /// Đếm todo cho 1 ngày tương lai — giả từ 0..5 deterministic.
  static int todoCountForDate(DateTime date) {
    final doy = date.difference(DateTime(date.year)).inDays;
    return (doy % 5);
  }
}
