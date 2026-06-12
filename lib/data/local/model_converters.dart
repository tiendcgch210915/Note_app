import 'package:drift/drift.dart';

import 'database.dart'; // provides generated *TableCompanion types from database.g.dart
import '../../models/checklist_category.dart';
import '../../models/habit.dart';
import '../../models/habit_log.dart';
import '../../models/note.dart';
import '../../models/run.dart';
import '../../models/run_item.dart';
import '../../models/tag.dart';
import '../../models/template.dart';
import '../../models/template_item.dart';
import '../../models/todo.dart';
import '../../utils/json_utils.dart';
import '../../utils/uuid_utils.dart';

/// Converters between domain models (used by UI) and Drift companion objects
/// (used for local DB writes).

// ─── Tag ──────────────────────────────────────────────────────────────────

TagsTableCompanion tagToCompanion(Tag tag, String userId) => TagsTableCompanion(
  id: Value(tag.id),
  name: Value(tag.name),
  color: Value(formatColorHex(tag.color)),
  userId: Value(tag.userId ?? userId),
  createdAt: Value(tag.createdAt?.toUtc().toIso8601String() ?? nowIso()),
  updatedAt: Value(tag.updatedAt?.toUtc().toIso8601String() ?? nowIso()),
  deletedAt: Value(tag.deletedAt?.toUtc().toIso8601String()),
);

// ─── Todo ─────────────────────────────────────────────────────────────────

TodosTableCompanion todoToCompanion(Todo todo, String userId) =>
    TodosTableCompanion(
      id: Value(todo.id),
      userId: Value(userId),
      parentId: Value(todo.parentId),
      title: Value(todo.title),
      description: Value(todo.description),
      status: Value(todo.status.backendValue),
      position: Value(todo.position),
      isFrog: Value(todo.isFrog),
      frogDate: Value(
        todo.frogDate != null ? formatDateOnly(todo.frogDate!) : null,
      ),
      isImportant: Value(todo.isImportant),
      isUrgent: Value(todo.isUrgent),
      estimatedMinutes: Value(todo.estimatedMinutes),
      actualMinutes: Value(todo.actualMinutes),
      startAt: Value(todo.startAt?.toUtc().toIso8601String()),
      dueAt: Value(todo.dueAt?.toUtc().toIso8601String()),
      scheduledDate: Value(
        todo.scheduledDate != null ? formatDateOnly(todo.scheduledDate!) : null,
      ),
      triggerAfterTodoId: Value(todo.triggerAfterTodoId),
      completedAt: Value(todo.completedAt?.toUtc().toIso8601String()),
      createdAt: Value(todo.createdAt.toUtc().toIso8601String()),
      updatedAt: Value(todo.updatedAt.toUtc().toIso8601String()),
      recurrenceType: Value(todo.recurrenceType),
      recurrenceInterval: Value(
        todo.recurrenceType != null ? todo.recurrenceInterval : null,
      ),
      recurrenceWeekdays: Value(todo.recurrenceDaysOfWeek),
      recurrenceEndDate: Value(todo.recurrenceEndDate),
      recurrenceTemplateId: Value(todo.recurrenceTemplateId),
    );

// ─── Note ─────────────────────────────────────────────────────────────────

NotesTableCompanion noteToCompanion(Note note, String userId) =>
    NotesTableCompanion(
      id: Value(note.id),
      userId: Value(userId),
      title: Value(note.title),
      type: Value(note.type.backendValue),
      body: Value(note.body),
      cornellCue: Value(note.cornellCue),
      cornellSummary: Value(note.cornellSummary),
      isPinned: Value(note.isPinned),
      createdAt: Value(note.createdAt.toUtc().toIso8601String()),
      updatedAt: Value(note.updatedAt.toUtc().toIso8601String()),
    );

// ─── Habit ────────────────────────────────────────────────────────────────

HabitsTableCompanion habitToCompanion(Habit habit, String userId) =>
    HabitsTableCompanion(
      id: Value(habit.id),
      userId: Value(userId),
      title: Value(habit.title),
      description: Value(habit.description),
      iconName: Value(habit.iconName),
      color: Value(formatColorHex(habit.color)),
      frequencyType: Value(habit.frequencyType.backendValue),
      targetPerPeriod: Value(habit.targetPerPeriod),
      activeWeekdays: Value(habit.activeWeekdays?.join(',') ?? ''),
      startDate: Value(formatDateOnly(habit.startDate)),
      endDate: Value(
        habit.endDate != null ? formatDateOnly(habit.endDate!) : null,
      ),
      currentStreak: Value(habit.currentStreak),
      longestStreak: Value(habit.longestStreak),
      isArchived: Value(habit.isArchived),
      createdAt: Value(nowIso()),
      updatedAt: Value(nowIso()),
    );

// ─── HabitLog ─────────────────────────────────────────────────────────────

HabitLogsTableCompanion habitLogToCompanion(HabitLog log, String userId) =>
    HabitLogsTableCompanion(
      id: Value(log.id),
      habitId: Value(log.habitId),
      userId: Value(userId),
      logDate: Value(formatDateOnly(log.logDate)),
      completed: Value(log.completed),
      note: Value(log.note),
      createdAt: Value(nowIso()),
      updatedAt: Value(nowIso()),
    );

// ─── Checklist category ───────────────────────────────────────────────────

ChecklistCategoriesTableCompanion checklistCategoryToCompanion(
  ChecklistCategory category,
) => ChecklistCategoriesTableCompanion(
  id: Value(category.id),
  userId: Value(category.userId),
  name: Value(category.name),
  slug: Value(category.slug),
  icon: Value(category.icon),
  color: Value(formatColorHex(category.color)),
  sortOrder: Value(category.sortOrder),
  isSystem: Value(category.isSystem),
  createdAt: Value(category.createdAt.toUtc().toIso8601String()),
  updatedAt: Value(category.updatedAt.toUtc().toIso8601String()),
  deletedAt: Value(category.deletedAt?.toUtc().toIso8601String()),
);

// ─── Template ─────────────────────────────────────────────────────────────

ChecklistTemplatesTableCompanion templateToCompanion(
  Template template,
  String? userId,
) => ChecklistTemplatesTableCompanion(
  id: Value(template.id),
  userId: Value(userId),
  title: Value(template.title),
  description: Value(template.description),
  icon: Value(template.icon),
  category: Value(template.category),
  categoryId: Value(template.categoryId),
  isSystem: Value(template.isSystem),
  sortOrder: Value(template.sortOrder),
  timesUsed: Value(template.timesUsed),
  lastUsedAt: Value(template.lastUsedAt?.toUtc().toIso8601String()),
  createdAt: Value(template.createdAt.toUtc().toIso8601String()),
  updatedAt: Value(template.updatedAt.toUtc().toIso8601String()),
);

// ─── TemplateItem ─────────────────────────────────────────────────────────

ChecklistTemplateItemsTableCompanion templateItemToCompanion(
  TemplateItem item,
) => ChecklistTemplateItemsTableCompanion(
  id: Value(item.id),
  templateId: Value(item.templateId),
  title: Value(item.title),
  description: Value(item.description),
  isRequired: Value(item.isRequired),
  orderIndex: Value(
    item.position,
  ), // model uses 'position', Drift table uses 'orderIndex'
  createdAt: Value(nowIso()),
  updatedAt: Value(nowIso()),
);

// ─── Run ──────────────────────────────────────────────────────────────────

ChecklistRunsTableCompanion runToCompanion(Run run, String userId) =>
    ChecklistRunsTableCompanion(
      id: Value(run.id),
      templateId: Value(run.templateId),
      userId: Value(userId),
      name: Value(run.name),
      status: Value(run.status.backendValue),
      completedAt: Value(run.completedAt?.toUtc().toIso8601String()),
      durationMs: Value(run.durationMs),
      createdAt: Value(run.startedAt.toUtc().toIso8601String()),
      updatedAt: Value(nowIso()),
    );

// ─── RunItem ──────────────────────────────────────────────────────────────

ChecklistRunItemsTableCompanion runItemToCompanion(RunItem item) =>
    ChecklistRunItemsTableCompanion(
      id: Value(item.id),
      runId: Value(item.runId),
      templateItemId: Value(item.templateItemId),
      title: Value(item.title),
      isRequired: Value(item.isRequired),
      status: Value(item.status.backendValue),
      completedAt: Value(item.completedAt?.toUtc().toIso8601String()),
      note: Value(item.note),
      orderIndex: Value(
        item.position,
      ), // model uses 'position', Drift table uses 'orderIndex'
      createdAt: Value(nowIso()),
      updatedAt: Value(nowIso()),
    );

// nowIso() is re-exported from uuid_utils for convenience
