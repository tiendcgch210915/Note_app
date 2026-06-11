import '../utils/json_utils.dart';
import 'tag.dart';

// ─── TodoStatus ───────────────────────────────────────────────────────────────

enum TodoStatus {
  open,
  inProgress,
  done,
  archived;

  String get label {
    switch (this) {
      case TodoStatus.open:
        return 'Mở';
      case TodoStatus.inProgress:
        return 'Đang làm';
      case TodoStatus.done:
        return 'Hoàn thành';
      case TodoStatus.archived:
        return 'Lưu trữ';
    }
  }

  /// Mapping backend string ↔ enum.
  String get backendValue {
    switch (this) {
      case TodoStatus.open:
        return 'open';
      case TodoStatus.inProgress:
        return 'in_progress';
      case TodoStatus.done:
        return 'done';
      case TodoStatus.archived:
        return 'archived';
    }
  }

  static TodoStatus parse(String s) {
    switch (s) {
      case 'in_progress':
        return TodoStatus.inProgress;
      case 'done':
        return TodoStatus.done;
      case 'archived':
        return TodoStatus.archived;
      default:
        return TodoStatus.open;
    }
  }
}

class Todo {
  final String id;
  final String? parentId;
  final String title;
  final String? description;
  final TodoStatus status;
  final int position;
  final bool isFrog;
  final DateTime? frogDate;
  final bool? isImportant;
  final bool? isUrgent;
  final int? estimatedMinutes;
  final int? actualMinutes;
  final DateTime? startAt;
  final DateTime? dueAt;
  final DateTime? scheduledDate;
  final String? triggerAfterTodoId;
  final List<String>
  tagIds; // dùng cho mock; backend không trả riêng — đã trong tags
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── Recurrence ────────────────────────────────────────────────
  /// "daily" | "weekly" | "custom" | null.
  final String? recurrenceType;

  /// Number of periods between occurrences (≥ 1). Defaults to 1.
  final int recurrenceInterval;

  /// Comma-separated ISO weekday numbers "1,3,5" (Mon=1…Sun=7).
  /// Used when recurrenceType == "weekly" or "custom".
  /// Maps to DB column `recurrenceWeekdays` / JSON key `recurrence_days_of_week`.
  final String? recurrenceDaysOfWeek;

  /// Inclusive end date "YYYY-MM-DD" after which no more instances are created.
  final String? recurrenceEndDate;

  /// null → this todo IS the recurrence template.
  /// non-null → this todo is an instance generated from that template.
  final String? recurrenceTemplateId;

  const Todo({
    required this.id,
    this.parentId,
    required this.title,
    this.description,
    this.status = TodoStatus.open,
    this.position = 0,
    this.isFrog = false,
    this.frogDate,
    this.isImportant,
    this.isUrgent,
    this.estimatedMinutes,
    this.actualMinutes,
    this.startAt,
    this.dueAt,
    this.scheduledDate,
    this.triggerAfterTodoId,
    this.tagIds = const [],
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.recurrenceType,
    this.recurrenceInterval = 1,
    this.recurrenceDaysOfWeek,
    this.recurrenceEndDate,
    this.recurrenceTemplateId,
  });

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'] as String,
      parentId: json['parent_id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      status: TodoStatus.parse(json['status'] as String? ?? 'open'),
      position: (json['position'] as num?)?.toInt() ?? 0,
      isFrog: jsonBool(json['is_frog']),
      frogDate: jsonDateOnlyNullable(json['frog_date'] as String?),
      isImportant: jsonBoolNullable(json['is_important']),
      isUrgent: jsonBoolNullable(json['is_urgent']),
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt(),
      actualMinutes: (json['actual_minutes'] as num?)?.toInt(),
      startAt: jsonDateNullable(json['start_at'] as String?),
      dueAt: jsonDateNullable(json['due_at'] as String?),
      scheduledDate: jsonDateOnlyNullable(json['scheduled_date'] as String?),
      triggerAfterTodoId: json['trigger_after_todo_id'] as String?,
      tagIds: const [],
      completedAt: jsonDateNullable(json['completed_at'] as String?),
      createdAt: jsonDate(json['created_at'] as String),
      updatedAt: jsonDate(json['updated_at'] as String),
      recurrenceType: json['recurrence_type'] as String?,
      recurrenceInterval: (json['recurrence_interval'] as num?)?.toInt() ?? 1,
      recurrenceDaysOfWeek: json['recurrence_days_of_week'] as String?,
      recurrenceEndDate: json['recurrence_end_date'] as String?,
      recurrenceTemplateId: json['recurrence_template_id'] as String?,
    );
  }

  /// Build body cho POST/PATCH. Chỉ include field non-null (để PATCH partial work).
  Map<String, dynamic> toUpdateJson({
    String? title,
    String? description,
    String? parentId,
    DateTime? scheduledDate,
    bool clearScheduledDate = false,
    TodoStatus? status,
    bool? isFrog,
    DateTime? frogDate,
    bool? isImportant,
    bool? isUrgent,
    int? estimatedMinutes,
    DateTime? startAt,
    DateTime? dueAt,
    String? triggerAfterTodoId,
    bool clearTriggerAfterTodo = false,
    int? position,
  }) {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (parentId != null) 'parent_id': parentId,
      if (clearScheduledDate)
        'scheduled_date': null
      else if (scheduledDate != null)
        'scheduled_date': formatDateOnly(scheduledDate),
      if (status != null) 'status': status.backendValue,
      if (isFrog != null) 'is_frog': isFrog,
      if (frogDate != null) 'frog_date': formatDateOnly(frogDate),
      if (isImportant != null) 'is_important': isImportant,
      if (isUrgent != null) 'is_urgent': isUrgent,
      if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      if (startAt != null) 'start_at': formatIsoDate(startAt),
      if (dueAt != null) 'due_at': formatIsoDate(dueAt),
      if (clearTriggerAfterTodo)
        'trigger_after_todo_id': null
      else if (triggerAfterTodoId != null)
        'trigger_after_todo_id': triggerAfterTodoId,
      if (position != null) 'position': position,
    };
  }

  Todo copyWith({
    TodoStatus? status,
    DateTime? completedAt,
    bool? isFrog,
    DateTime? frogDate,
    bool? isImportant,
    bool? isUrgent,
    DateTime? scheduledDate,
  }) {
    return Todo(
      id: id,
      parentId: parentId,
      title: title,
      description: description,
      status: status ?? this.status,
      position: position,
      isFrog: isFrog ?? this.isFrog,
      frogDate: frogDate ?? this.frogDate,
      isImportant: isImportant ?? this.isImportant,
      isUrgent: isUrgent ?? this.isUrgent,
      estimatedMinutes: estimatedMinutes,
      actualMinutes: actualMinutes,
      startAt: startAt,
      dueAt: dueAt,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      triggerAfterTodoId: triggerAfterTodoId,
      tagIds: tagIds,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      recurrenceType: recurrenceType,
      recurrenceInterval: recurrenceInterval,
      recurrenceDaysOfWeek: recurrenceDaysOfWeek,
      recurrenceEndDate: recurrenceEndDate,
      recurrenceTemplateId: recurrenceTemplateId,
    );
  }

  bool get isDone => status == TodoStatus.done;

  // ── Recurrence helpers ────────────────────────────────────────
  /// True when this todo defines a recurrence pattern (no scheduled_date).
  bool get isRecurrenceTemplate =>
      recurrenceType != null && recurrenceTemplateId == null;

  /// True when this todo was generated from a recurrence template.
  bool get isRecurrenceInstance => recurrenceTemplateId != null;

  /// True for both templates and instances.
  bool get isRecurring => isRecurrenceTemplate || isRecurrenceInstance;

  /// Parsed list of ISO weekday ints (1=Mon … 7=Sun).
  List<int> get activeDaysOfWeek => (recurrenceDaysOfWeek ?? '').isEmpty
      ? []
      : recurrenceDaysOfWeek!.split(',').map(int.parse).toList();

  /// Human-readable label for the recurrence pattern (Vietnamese).
  String get recurrenceLabel {
    if (!isRecurring) return '';
    final interval = recurrenceInterval;
    switch (recurrenceType) {
      case 'daily':
        return interval == 1 ? 'Mỗi ngày' : 'Mỗi $interval ngày';
      case 'weekly':
        final days = activeDaysOfWeek;
        if (days.isEmpty) return 'Mỗi tuần';
        const names = ['', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
        return days.map((d) => names[d]).join(', ');
      case 'custom':
        return 'Tùy chỉnh';
      default:
        // Instance: show template ID short form
        return 'Lặp lại';
    }
  }
}

/// Response F-T3 — Todo + cờ has_subtasks (nhanh để hiện expand icon).
class DayTopLevelTodo {
  final Todo todo;
  final bool hasSubtasks;

  const DayTopLevelTodo({required this.todo, required this.hasSubtasks});

  factory DayTopLevelTodo.fromJson(Map<String, dynamic> json) {
    return DayTopLevelTodo(
      todo: Todo.fromJson(json),
      hasSubtasks: jsonBool(json['has_subtasks']),
    );
  }
}

/// Note nhỏ gọn liên kết tới todo. Tránh import Note để không circular.
class LinkedTodoNote {
  final String id;
  final String title;

  const LinkedTodoNote({required this.id, required this.title});

  factory LinkedTodoNote.fromJson(Map<String, dynamic> json) {
    return LinkedTodoNote(
      id: json['id'] as String,
      title: json['title'] as String,
    );
  }
}

/// Response F-T4 GET /todos/:id và F-T1 POST /todos.
class TodoWithRelations {
  final Todo todo;
  final List<Tag> tags;
  final List<Todo> subtasks;
  final List<LinkedTodoNote> linkedNotes;

  const TodoWithRelations({
    required this.todo,
    required this.tags,
    required this.subtasks,
    required this.linkedNotes,
  });

  factory TodoWithRelations.fromJson(Map<String, dynamic> json) {
    return TodoWithRelations(
      todo: Todo.fromJson(json['todo'] as Map<String, dynamic>),
      tags:
          (json['tags'] as List?)
              ?.map((e) => Tag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      subtasks:
          (json['subtasks'] as List?)
              ?.map((e) => Todo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      linkedNotes:
          (json['linked_notes'] as List?)
              ?.map((e) => LinkedTodoNote.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
