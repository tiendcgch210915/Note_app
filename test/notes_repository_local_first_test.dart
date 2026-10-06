import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/local/model_converters.dart';
import 'package:todonote/data/notes_repository.dart';
import 'package:todonote/models/note.dart';
import 'package:todonote/models/tag.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/sync/connectivity_sync.dart';

void main() {
  const userId = 'user-1';
  const bodyDelta = {
    'ops': [
      {'insert': 'Nội dung chính\n'},
    ],
  };

  late AppDatabase db;
  late NotesRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = NotesRepository.forTesting(db, userId: userId);
  });

  tearDown(() async {
    ConnectivitySync.instance.cancelPending();
    await db.close();
  });

  test('creates Free note offline and enqueues create', () async {
    final detail = await repository.create(
      title: 'Ý tưởng',
      type: NoteType.free,
      body: 'Nội dung',
      bodyDelta: bodyDelta,
    );

    expect(detail.note.title, 'Ý tưởng');
    expect(await db.notesDao.getNoteById(detail.note.id), isNotNull);
    final queue = await db.syncDao.getRowsForUser(userId: userId);
    expect(queue, hasLength(1));
    expect(queue.single.operation, 'create');
    expect(queue.single.entityType, 'note');
  });

  test('offline note payload preserves non-url inline link text', () async {
    const linkedDelta = {
      'ops': [
        {
          'insert': 'abandon',
          'attributes': {'bold': true, 'link': 'bỏ rơi; từ bỏ'},
        },
        {'insert': '\n'},
      ],
    };

    await repository.create(
      title: 'English vocabulary',
      type: NoteType.free,
      body: 'abandon',
      bodyDelta: linkedDelta,
    );

    final queue = await db.syncDao.getRowsForUser(userId: userId);
    final payload = jsonDecode(queue.single.payload) as Map<String, dynamic>;
    expect(payload['body_delta'], linkedDelta);
  });

  test(
    'creates Cornell with Notes only and nullable optional sections',
    () async {
      final detail = await repository.create(
        title: 'Bài học',
        type: NoteType.cornell,
        body: 'Nội dung chính',
        bodyDelta: bodyDelta,
      );

      expect(detail.note.type, NoteType.cornell);
      expect(detail.note.cornellCue, isNull);
      expect(detail.note.cornellSummary, isNull);
      final queue = await db.syncDao.getRowsForUser(userId: userId);
      final payload = jsonDecode(queue.single.payload) as Map<String, dynamic>;
      expect(payload['cornell_cue'], isNull);
      expect(payload['cornell_summary'], isNull);
      expect(payload['body_delta'], bodyDelta);
    },
  );

  test('updates Cornell sections independently', () async {
    final created = await repository.create(
      title: 'Cornell',
      type: NoteType.cornell,
      body: 'Body',
      bodyDelta: bodyDelta,
      cornellSummary: 'Summary',
      cornellSummaryDelta: const {
        'ops': [
          {'insert': 'Summary\n'},
        ],
      },
    );
    const cueDelta = {
      'ops': [
        {'insert': 'Cue\n'},
      ],
    };

    await repository.update(
      created.note.id,
      cornellCue: 'Cue',
      cornellCueDelta: cueDelta,
    );
    final detail = await repository.getLocalDetail(created.note.id);

    expect(detail!.note.body, 'Body');
    expect(detail.note.bodyDelta, bodyDelta);
    expect(detail.note.cornellCue, 'Cue');
    expect(detail.note.cornellCueDelta, cueDelta);
    expect(detail.note.cornellSummary, 'Summary');
  });

  test('content autosave keeps full relation arrays', () async {
    final source = await repository.create(
      title: 'Source',
      type: NoteType.free,
      body: 'Old',
      bodyDelta: bodyDelta,
    );
    final target = await repository.create(
      title: 'Target',
      type: NoteType.free,
      body: 'Target',
      bodyDelta: bodyDelta,
    );
    final tag = Tag(
      id: 'tag-1',
      userId: userId,
      name: 'Study',
      color: Colors.blue,
      createdAt: DateTime.utc(2026, 6, 26),
      updatedAt: DateTime.utc(2026, 6, 26),
    );
    await db.todosDao.upsertTag(tagToCompanion(tag, userId));
    final todo = Todo(
      id: 'todo-1',
      title: 'Ôn bài',
      createdAt: DateTime.utc(2026, 6, 26),
      updatedAt: DateTime.utc(2026, 6, 26),
    );
    await db.todosDao.upsertTodo(todoToCompanion(todo, userId));

    await repository.attachTag(source.note.id, tagId: tag.id);
    await repository.addLink(source.note.id, target.note.id, label: 'Ref');
    await repository.linkTodo(source.note.id, todo.id);
    await repository.update(
      source.note.id,
      body: 'New',
      bodyDelta: const {
        'ops': [
          {'insert': 'New\n'},
        ],
      },
    );

    final pending = await db.syncDao.getPendingForEntity(
      'note',
      source.note.id,
      userId: userId,
    );
    final payload = jsonDecode(pending!.payload) as Map<String, dynamic>;
    expect(payload['tag_ids'], [tag.id]);
    expect(payload['linked_todo_ids'], [todo.id]);
    expect(payload['note_links'], [
      {'target_note_id': target.note.id, 'label': 'Ref'},
    ]);
  });

  test('create then delete before sync removes pointless operation', () async {
    final created = await repository.create(
      title: 'Temporary',
      type: NoteType.free,
      body: 'X',
      bodyDelta: bodyDelta,
    );

    await repository.delete(created.note.id);

    expect(await db.syncDao.getRowsForUser(userId: userId), isEmpty);
    expect(
      await db.notesDao.getNoteByIdIncludingDeleted(created.note.id),
      isNull,
    );
  });

  test('offline list and detail read Drift cache with relations', () async {
    final created = await repository.create(
      title: 'Cached',
      type: NoteType.cornell,
      body: 'Body',
      bodyDelta: bodyDelta,
    );

    final list = await repository.listLocal(type: 'cornell');
    final detail = await repository.getLocalDetail(created.note.id);

    expect(list.map((note) => note.id), contains(created.note.id));
    expect(detail?.note.body, 'Body');
  });

  test(
    'delete canonical note creates tombstone and cleans relations',
    () async {
      final now = DateTime.utc(2026, 6, 26);
      final note = Note(
        id: 'server-note',
        userId: userId,
        title: 'Server',
        createdAt: now,
        updatedAt: now,
      );
      await db.notesDao.upsertNote(noteToCompanion(note, userId));
      await db.notesDao.setNoteTags(note.id, const ['missing-tag']);
      await db.notesDao.upsertNoteTodoLink(
        NoteTodoLinksTableCompanion.insert(
          noteId: note.id,
          todoId: 'todo-1',
          createdAt: now.toIso8601String(),
        ),
      );

      await repository.delete(note.id);

      final row = await db.notesDao.getNoteByIdIncludingDeleted(note.id);
      expect(row?.deletedAt, isNotNull);
      expect(await db.notesDao.getTagIdsForNote(note.id), isEmpty);
      expect(await db.notesDao.getTodoLinksForNote(note.id), isEmpty);
      final queue = await db.syncDao.getRowsForUser(userId: userId);
      expect(queue.single.operation, 'delete');
    },
  );
}
