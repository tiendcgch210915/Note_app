// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notes_dao.dart';

// ignore_for_file: type=lint
mixin _$NotesDaoMixin on DatabaseAccessor<AppDatabase> {
  $NotesTableTable get notesTable => attachedDatabase.notesTable;
  $NoteTagsTableTable get noteTagsTable => attachedDatabase.noteTagsTable;
  $TagsTableTable get tagsTable => attachedDatabase.tagsTable;
  $NoteLinksTableTable get noteLinksTable => attachedDatabase.noteLinksTable;
  $NoteTodoLinksTableTable get noteTodoLinksTable =>
      attachedDatabase.noteTodoLinksTable;
  NotesDaoManager get managers => NotesDaoManager(this);
}

class NotesDaoManager {
  final _$NotesDaoMixin _db;
  NotesDaoManager(this._db);
  $$NotesTableTableTableManager get notesTable =>
      $$NotesTableTableTableManager(_db.attachedDatabase, _db.notesTable);
  $$NoteTagsTableTableTableManager get noteTagsTable =>
      $$NoteTagsTableTableTableManager(_db.attachedDatabase, _db.noteTagsTable);
  $$TagsTableTableTableManager get tagsTable =>
      $$TagsTableTableTableManager(_db.attachedDatabase, _db.tagsTable);
  $$NoteLinksTableTableTableManager get noteLinksTable =>
      $$NoteLinksTableTableTableManager(
        _db.attachedDatabase,
        _db.noteLinksTable,
      );
  $$NoteTodoLinksTableTableTableManager get noteTodoLinksTable =>
      $$NoteTodoLinksTableTableTableManager(
        _db.attachedDatabase,
        _db.noteTodoLinksTable,
      );
}
