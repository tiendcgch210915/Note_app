import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'dao/checklists_dao.dart';
import 'dao/habits_dao.dart';
import 'dao/notes_dao.dart';
import 'dao/sync_dao.dart';
import 'dao/todos_dao.dart';
import 'tables.dart';

part 'database.g.dart';

/// Singleton SQLite database backed by Drift.
///
/// ⚠️  After any change to this file or tables.dart:
///   dart run build_runner build --delete-conflicting-outputs
@DriftDatabase(
  tables: [
    UsersTable,
    TagsTable,
    TodosTable,
    TodoTagsTable,
    NotesTable,
    NoteTagsTable,
    NoteLinksTable,
    NoteTodoLinksTable,
    HabitsTable,
    HabitLogsTable,
    ChecklistTemplatesTable,
    ChecklistTemplateItemsTable,
    ChecklistRunsTable,
    ChecklistRunItemsTable,
    RemindersTable,
    SyncQueueTable,
    SyncMetaTable,
  ],
  daos: [
    TodosDao,
    NotesDao,
    HabitsDao,
    ChecklistsDao,
    SyncDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(_openConnection());

  static final AppDatabase instance = AppDatabase._();

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // v1 → v2: add recurrence columns to todos (reserved).
          if (from < 2) {
            await m.addColumn(todosTable, todosTable.recurrenceType);
            await m.addColumn(todosTable, todosTable.recurrenceInterval);
            await m.addColumn(todosTable, todosTable.recurrenceWeekdays);
          }
          // v2 → v3: add recurrence end-date + template-id columns.
          if (from < 3) {
            await m.addColumn(todosTable, todosTable.recurrenceEndDate);
            await m.addColumn(todosTable, todosTable.recurrenceTemplateId);
          }
        },
      );
}

/// Opens the SQLite connection using drift_flutter (driftDatabase helper).
/// On Android/iOS this is the app-documents directory; on desktop it is the
/// current working directory. Name can be anything — keep it stable.
QueryExecutor _openConnection() {
  return driftDatabase(name: 'todonote_db');
}
