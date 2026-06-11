// ignore_for_file: type=lint
import 'package:drift/drift.dart';

// ─────────────────────────────────────────────────────────────
// Reusable mixin: soft-delete timestamps (createdAt, updatedAt, deletedAt)
// ─────────────────────────────────────────────────────────────

mixin Timestamps on Table {
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();
}

// ─────────────────────────────────────────────────────────────
// Users
// ─────────────────────────────────────────────────────────────

@DataClassName('UserRow')
class UsersTable extends Table with Timestamps {
  @override
  String get tableName => 'users';

  TextColumn get id => text()();
  TextColumn get email => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get timezone => text().nullable()();
  TextColumn get settings => text().nullable()(); // JSON string

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Tags
// ─────────────────────────────────────────────────────────────

@DataClassName('TagRow')
class TagsTable extends Table with Timestamps {
  @override
  String get tableName => 'tags';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#888888'))();
  TextColumn get userId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Todos
// ─────────────────────────────────────────────────────────────

@DataClassName('TodoRow')
class TodosTable extends Table with Timestamps {
  @override
  String get tableName => 'todos';

  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  BoolColumn get isFrog => boolean().withDefault(const Constant(false))();
  TextColumn get frogDate => text().nullable()(); // date-only "YYYY-MM-DD"
  BoolColumn get isImportant => boolean().nullable()();
  BoolColumn get isUrgent => boolean().nullable()();
  IntColumn get estimatedMinutes => integer().nullable()();
  IntColumn get actualMinutes => integer().nullable()();
  TextColumn get startAt => text().nullable()();
  TextColumn get dueAt => text().nullable()();
  // M-RECON: scheduledDate nullable (date-only string "YYYY-MM-DD")
  TextColumn get scheduledDate => text().nullable()();
  TextColumn get triggerAfterTodoId => text().nullable()();
  TextColumn get completedAt => text().nullable()();

  // Recurrence columns.
  TextColumn get recurrenceType => text().nullable()();
  IntColumn get recurrenceInterval => integer().nullable()();

  /// Stored as "1,3,5" (Mon=1…Sun=7); JSON key: recurrence_days_of_week.
  TextColumn get recurrenceWeekdays => text().nullable()();
  TextColumn get recurrenceEndDate => text().nullable()(); // "YYYY-MM-DD"
  /// null → this row IS the template; non-null → this row is an instance.
  TextColumn get recurrenceTemplateId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Todo ↔ Tag junction
// ─────────────────────────────────────────────────────────────

@DataClassName('TodoTagRow')
class TodoTagsTable extends Table {
  @override
  String get tableName => 'todo_tags';

  TextColumn get todoId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column> get primaryKey => {todoId, tagId};
}

// ─────────────────────────────────────────────────────────────
// Notes
// ─────────────────────────────────────────────────────────────

@DataClassName('NoteRow')
class NotesTable extends Table with Timestamps {
  @override
  String get tableName => 'notes';

  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get type => text().withDefault(const Constant('free'))();
  TextColumn get body => text().nullable()();
  TextColumn get cornellCue => text().nullable()();
  TextColumn get cornellSummary => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Note ↔ Tag junction
// ─────────────────────────────────────────────────────────────

@DataClassName('NoteTagRow')
class NoteTagsTable extends Table {
  @override
  String get tableName => 'note_tags';

  TextColumn get noteId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}

// ─────────────────────────────────────────────────────────────
// Note outgoing links (note → note)
// ─────────────────────────────────────────────────────────────

@DataClassName('NoteLinkRow')
class NoteLinksTable extends Table {
  @override
  String get tableName => 'note_links';

  TextColumn get id => text()();
  TextColumn get sourceNoteId => text()();
  TextColumn get targetNoteId => text()();
  TextColumn get label => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Note ↔ Todo junction
// ─────────────────────────────────────────────────────────────

@DataClassName('NoteTodoLinkRow')
class NoteTodoLinksTable extends Table {
  @override
  String get tableName => 'note_todo_links';

  TextColumn get noteId => text()();
  TextColumn get todoId => text()();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {noteId, todoId};
}

// ─────────────────────────────────────────────────────────────
// Habits
// ─────────────────────────────────────────────────────────────

@DataClassName('HabitRow')
class HabitsTable extends Table with Timestamps {
  @override
  String get tableName => 'habits';

  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get iconName => text().nullable()();
  TextColumn get color => text().withDefault(const Constant('#4CAF50'))();
  TextColumn get frequencyType => text().withDefault(const Constant('daily'))();
  IntColumn get targetPerPeriod => integer().withDefault(const Constant(1))();
  // Stored as comma-separated "1,3,5" like backend
  TextColumn get activeWeekdays => text().nullable()();
  TextColumn get startDate => text()(); // date-only
  TextColumn get endDate => text().nullable()(); // date-only
  IntColumn get currentStreak => integer().withDefault(const Constant(0))();
  IntColumn get longestStreak => integer().withDefault(const Constant(0))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Habit logs
// ─────────────────────────────────────────────────────────────

@DataClassName('HabitLogRow')
class HabitLogsTable extends Table with Timestamps {
  @override
  String get tableName => 'habit_logs';

  TextColumn get id => text()();
  TextColumn get habitId => text()();
  TextColumn get userId => text()();
  TextColumn get logDate => text()(); // date-only "YYYY-MM-DD"
  BoolColumn get completed => boolean().withDefault(const Constant(true))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Checklist templates
// ─────────────────────────────────────────────────────────────

@DataClassName('ChecklistCategoryRow')
class ChecklistCategoriesTable extends Table with Timestamps {
  @override
  String get tableName => 'checklist_categories';

  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get slug => text()();
  TextColumn get icon => text().nullable()();
  TextColumn get color => text().withDefault(const Constant('#4F46E5'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TemplateRow')
class ChecklistTemplatesTable extends Table with Timestamps {
  @override
  String get tableName => 'checklist_templates';

  TextColumn get id => text()();
  TextColumn get userId => text().nullable()(); // null for system templates
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get icon => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  // M-RECON: isSystem column
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  IntColumn get timesUsed => integer().withDefault(const Constant(0))();
  TextColumn get lastUsedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Checklist template items
// ─────────────────────────────────────────────────────────────

@DataClassName('TemplateItemRow')
class ChecklistTemplateItemsTable extends Table with Timestamps {
  @override
  String get tableName => 'checklist_template_items';

  TextColumn get id => text()();
  TextColumn get templateId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Checklist runs
// ─────────────────────────────────────────────────────────────

@DataClassName('RunRow')
class ChecklistRunsTable extends Table with Timestamps {
  @override
  String get tableName => 'checklist_runs';

  TextColumn get id => text()();
  TextColumn get templateId => text()();
  TextColumn get userId => text()();
  TextColumn get name => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('in_progress'))();
  TextColumn get completedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Checklist run items
// ─────────────────────────────────────────────────────────────

@DataClassName('RunItemRow')
class ChecklistRunItemsTable extends Table with Timestamps {
  @override
  String get tableName => 'checklist_run_items';

  TextColumn get id => text()();
  TextColumn get runId => text()();
  TextColumn get templateItemId => text().nullable()();
  TextColumn get title => text()();
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending/done/skipped
  TextColumn get completedAt => text().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Reminders (dormant – backend not yet built; keep table, no sync)
// ─────────────────────────────────────────────────────────────

@DataClassName('ReminderRow')
class RemindersTable extends Table with Timestamps {
  @override
  String get tableName => 'reminders';

  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get entityType => text()(); // 'todo' | 'habit' | 'note'
  TextColumn get entityId => text()();
  TextColumn get remindAt => text()(); // ISO datetime
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  TextColumn get recurrenceRule => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────
// Sync queue
// ─────────────────────────────────────────────────────────────

@DataClassName('SyncQueueRow')
class SyncQueueTable extends Table {
  @override
  String get tableName => 'sync_queue';

  /// Auto-increment PK (simple integer for ordering)
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType =>
      text()(); // 'todo','note','tag','habit','habit_log','checklist_template','checklist_template_item','checklist_run','checklist_run_item','user'
  TextColumn get entityId => text()();
  TextColumn get operation => text()(); // 'create' | 'update' | 'delete'
  TextColumn get payload => text()(); // JSON string of the full entity or patch
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Epoch millis; null = ready now
  IntColumn get nextRetryAt => integer().nullable()();
  TextColumn get createdAt => text()();
}

// ─────────────────────────────────────────────────────────────
// Sync metadata (key-value store)
// ─────────────────────────────────────────────────────────────

@DataClassName('SyncMetaRow')
class SyncMetaTable extends Table {
  @override
  String get tableName => 'sync_meta';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
