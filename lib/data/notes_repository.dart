import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/note.dart';
import '../models/tag.dart';
import '../sync/connectivity_sync.dart';
import '../sync/sync_payload.dart';
import '../utils/json_utils.dart';
import '../utils/note_delta_utils.dart';
import '../utils/note_local_events.dart';
import '../utils/uuid_utils.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'auth_storage.dart';
import 'local/database.dart';
import 'local/model_converters.dart';
import 'tags_repository.dart';

class NotesRepository {
  NotesRepository._({
    ApiClient? client,
    AppDatabase? database,
    String? userIdOverride,
  }) : _client = client ?? ApiClient.instance,
       _db = database ?? AppDatabase.instance,
       _userIdOverride = userIdOverride;

  static final NotesRepository instance = NotesRepository._();

  factory NotesRepository.forTesting(
    AppDatabase database, {
    required String userId,
  }) {
    return NotesRepository._(database: database, userIdOverride: userId);
  }

  final ApiClient _client;
  final AppDatabase _db;
  final String? _userIdOverride;

  String get _userId =>
      _userIdOverride ??
      AuthStorage.instance.currentUserJson?['id'] as String? ??
      '';

  Future<({List<Note> items, String? nextCursor})> list({
    String? cursor,
    int? limit,
    String? q,
    bool? pinned,
    String? type,
  }) async {
    try {
      return await refreshList(
        cursor: cursor,
        limit: limit,
        q: q,
        pinned: pinned,
        type: type,
      );
    } on ApiException {
      return (
        items: await listLocal(
          limit: limit ?? 50,
          q: q,
          pinned: pinned,
          type: type,
        ),
        nextCursor: null,
      );
    }
  }

  Future<List<Note>> listLocal({
    int limit = 50,
    String? q,
    bool? pinned,
    String? type,
  }) async {
    final rows = await _db.notesDao.getNotes(
      userId: _requireUserId(),
      q: q?.trim(),
      pinned: pinned,
      type: type,
      limit: limit,
    );
    final result = <Note>[];
    for (final row in rows) {
      final tags = (await _db.notesDao.getTagsForNote(
        row.id,
      )).map(_tagRowToModel).toList();
      result.add(_noteRowToModel(row).copyWith(tags: tags));
    }
    return result;
  }

  Future<({List<Note> items, String? nextCursor})> refreshList({
    String? cursor,
    int? limit,
    String? q,
    bool? pinned,
    String? type,
  }) async {
    final response = await _client.get(
      '/notes',
      query: {
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': limit,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (pinned != null) 'pinned': pinned,
        if (type != null && type.isNotEmpty) 'type': type,
      },
    );
    final map = Map<String, dynamic>.from(response as Map);
    final serverNotes = ((map['items'] as List?) ?? const [])
        .map((item) => Note.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    for (final note in serverNotes) {
      if (await _hasPendingNote(note.id)) continue;
      await _db.notesDao.upsertNote(noteToCompanion(note, _requireUserId()));
    }
    return (
      items: await listLocal(
        limit: limit ?? 50,
        q: q,
        pinned: pinned,
        type: type,
      ),
      nextCursor: map['nextCursor'] as String? ?? map['next_cursor'] as String?,
    );
  }

  Future<NoteWithRelations> getDetail(String id) async {
    final local = await getLocalDetail(id);
    if (local != null) return local;
    return refreshDetail(id);
  }

  Future<NoteWithRelations?> getLocalDetail(String id) async {
    final row = await _db.notesDao.getNoteById(id);
    if (row == null || row.userId != _requireUserId()) return null;

    final tags = (await _db.notesDao.getTagsForNote(
      id,
    )).map(_tagRowToModel).toList();
    final outgoing = <OutgoingLink>[];
    for (final link in await _db.notesDao.getOutgoingLinks(id)) {
      final target = await _db.notesDao.getNoteById(link.targetNoteId);
      outgoing.add(
        OutgoingLink(
          id: link.id,
          sourceNoteId: link.sourceNoteId,
          targetNoteId: link.targetNoteId,
          label: link.label,
          createdAt: jsonDate(link.createdAt),
          targetTitle: target?.title ?? '(Note không còn tồn tại)',
        ),
      );
    }

    final incoming = <IncomingLink>[];
    for (final link in await _db.notesDao.getIncomingLinks(id)) {
      final source = await _db.notesDao.getNoteById(link.sourceNoteId);
      incoming.add(
        IncomingLink(
          id: link.id,
          sourceNoteId: link.sourceNoteId,
          targetNoteId: link.targetNoteId,
          label: link.label,
          createdAt: jsonDate(link.createdAt),
          sourceTitle: source?.title ?? '(Note không còn tồn tại)',
        ),
      );
    }

    final todos = <LinkedTodo>[];
    for (final junction in await _db.notesDao.getTodoLinksForNote(id)) {
      final todo = await _db.notesDao.getLinkedTodo(junction.todoId);
      if (todo == null) continue;
      todos.add(
        LinkedTodo(id: todo.id, title: todo.title, status: todo.status),
      );
    }

    return NoteWithRelations(
      note: _noteRowToModel(row).copyWith(tags: tags),
      tags: tags,
      outgoing: outgoing,
      incoming: incoming,
      todos: todos,
    );
  }

  Future<NoteWithRelations> refreshDetail(String id) async {
    if (await _hasPendingNote(id)) {
      final local = await getLocalDetail(id);
      if (local != null) return local;
    }

    final response = await _client.get('/notes/$id');
    final detail = NoteWithRelations.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
    await _cacheServerDetail(detail);
    return detail;
  }

  Future<NoteWithRelations> create({
    required String title,
    required NoteType type,
    String? body,
    String? cornellCue,
    String? cornellSummary,
    Map<String, dynamic>? bodyDelta,
    Map<String, dynamic>? cornellCueDelta,
    Map<String, dynamic>? cornellSummaryDelta,
    bool isPinned = false,
    List<String> tagIds = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final normalizedTitle = _normalizeTitle(title);
    final note = Note(
      id: newId(),
      userId: _requireUserId(),
      title: normalizedTitle,
      type: type,
      body: _nullableText(body),
      cornellCue: type == NoteType.cornell ? _nullableText(cornellCue) : null,
      cornellSummary: type == NoteType.cornell
          ? _nullableText(cornellSummary)
          : null,
      contentFormat:
          bodyDelta != null ||
              cornellCueDelta != null ||
              cornellSummaryDelta != null
          ? noteContentFormatQuill
          : noteContentFormatPlain,
      bodyDelta: sanitizeNoteDelta(bodyDelta),
      cornellCueDelta: type == NoteType.cornell
          ? sanitizeNoteDelta(cornellCueDelta)
          : null,
      cornellSummaryDelta: type == NoteType.cornell
          ? sanitizeNoteDelta(cornellSummaryDelta)
          : null,
      isPinned: isPinned,
      createdAt: now,
      updatedAt: now,
    );
    _validateNote(note);

    final distinctTagIds = tagIds.toSet().take(20).toList();
    await _db.transaction(() async {
      await _db.notesDao.upsertNote(noteToCompanion(note, _requireUserId()));
      await _db.notesDao.setNoteTags(note.id, distinctTagIds);
      await _enqueueStoredNote(note.id, operation: 'create');
    });
    _afterLocalWrite();
    return (await getLocalDetail(note.id))!;
  }

  Future<Note> update(
    String id, {
    String? title,
    NoteType? type,
    String? body,
    bool clearBody = false,
    String? cornellCue,
    bool clearCornellCue = false,
    String? cornellSummary,
    bool clearCornellSummary = false,
    Map<String, dynamic>? bodyDelta,
    bool clearBodyDelta = false,
    Map<String, dynamic>? cornellCueDelta,
    bool clearCornellCueDelta = false,
    Map<String, dynamic>? cornellSummaryDelta,
    bool clearCornellSummaryDelta = false,
    String? contentFormat,
    bool? isPinned,
  }) async {
    final row = await _db.notesDao.getNoteById(id);
    if (row == null || row.userId != _requireUserId()) {
      throw const ApiException(404, 'not_found', 'not_found');
    }
    final current = _noteRowToModel(row);
    final nextType = type ?? current.type;
    final convertingToFree =
        current.type == NoteType.cornell && nextType == NoteType.free;
    final hasDeltaChange =
        bodyDelta != null ||
        cornellCueDelta != null ||
        cornellSummaryDelta != null;

    final updated = current.copyWith(
      title: title == null ? null : _normalizeTitle(title),
      type: nextType,
      body: body == null ? null : _nullableText(body),
      clearBody: clearBody || (body != null && body.isEmpty),
      cornellCue: cornellCue == null ? null : _nullableText(cornellCue),
      clearCornellCue:
          clearCornellCue ||
          convertingToFree ||
          (cornellCue != null && cornellCue.isEmpty),
      cornellSummary: cornellSummary == null
          ? null
          : _nullableText(cornellSummary),
      clearCornellSummary:
          clearCornellSummary ||
          convertingToFree ||
          (cornellSummary != null && cornellSummary.isEmpty),
      contentFormat:
          contentFormat ?? (hasDeltaChange ? noteContentFormatQuill : null),
      bodyDelta: sanitizeNoteDelta(bodyDelta),
      clearBodyDelta: clearBodyDelta || (body != null && bodyDelta == null),
      cornellCueDelta: sanitizeNoteDelta(cornellCueDelta),
      clearCornellCueDelta:
          clearCornellCueDelta ||
          convertingToFree ||
          (cornellCue != null && cornellCueDelta == null),
      cornellSummaryDelta: sanitizeNoteDelta(cornellSummaryDelta),
      clearCornellSummaryDelta:
          clearCornellSummaryDelta ||
          convertingToFree ||
          (cornellSummary != null && cornellSummaryDelta == null),
      isPinned: isPinned,
      updatedAt: DateTime.now().toUtc(),
    );
    _validateNote(updated);

    await _db.transaction(() async {
      await _db.notesDao.upsertNote(noteToCompanion(updated, _requireUserId()));
      await _enqueueStoredNote(id, operation: 'update');
    });
    _afterLocalWrite();
    return updated;
  }

  Future<void> delete(String id) async {
    final row = await _db.notesDao.getNoteById(id);
    if (row == null || row.userId != _requireUserId()) return;
    final pending = await _db.syncDao.getPendingForEntity(
      'note',
      id,
      userId: _requireUserId(),
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction(() async {
      await _db.notesDao.softDeleteNote(id, now);
      await _db.notesDao.cleanJunctionsForDeletedNotes([id]);
      await _db.syncDao.enqueueSyncOp(
        userId: _requireUserId(),
        entityType: 'note',
        entityId: id,
        operation: 'delete',
        payload: jsonEncode({'id': id, 'updated_at': now, 'deleted_at': now}),
      );
      if (pending?.operation == 'create') {
        await _db.notesDao.hardDeleteNote(id);
      }
    });
    _afterLocalWrite();
  }

  Future<OutgoingLink> addLink(
    String sourceId,
    String targetId, {
    String? label,
  }) async {
    if (sourceId == targetId) {
      throw const ApiException(400, 'bad_input', 'Không thể tự liên kết note');
    }
    final existing = await _db.notesDao.getActiveNoteLink(sourceId, targetId);
    if (existing != null) {
      throw const ApiException(409, 'conflict', 'Liên kết đã tồn tại');
    }
    final target = await _db.notesDao.getNoteById(targetId);
    if (target == null) {
      throw const ApiException(404, 'not_found', 'not_found');
    }
    final normalizedLabel = _nullableText(label);
    if ((normalizedLabel?.length ?? 0) > 100) {
      throw const ApiException(400, 'bad_input', 'Nhãn tối đa 100 ký tự');
    }
    final now = DateTime.now().toUtc();
    final link = OutgoingLink(
      id: newId(),
      sourceNoteId: sourceId,
      targetNoteId: targetId,
      label: normalizedLabel,
      createdAt: now,
      targetTitle: target.title,
    );
    await _db.transaction(() async {
      await _db.notesDao.upsertNoteLink(
        NoteLinksTableCompanion.insert(
          id: link.id,
          sourceNoteId: link.sourceNoteId,
          targetNoteId: link.targetNoteId,
          label: Value(link.label),
          createdAt: now.toIso8601String(),
          updatedAt: now.toIso8601String(),
        ),
      );
      await _touchAndEnqueue(sourceId);
    });
    _afterLocalWrite();
    return link;
  }

  Future<void> removeLink(String sourceId, String targetId) async {
    await _db.transaction(() async {
      await _db.notesDao.removeNoteLink(sourceId, targetId);
      await _touchAndEnqueue(sourceId);
    });
    _afterLocalWrite();
  }

  Future<List<IncomingLink>> getBacklinks(String id) async {
    return (await getLocalDetail(id))?.incoming ?? const [];
  }

  Future<void> linkTodo(String noteId, String todoId) async {
    final existing = await _db.notesDao.getTodoLinksForNote(noteId);
    if (existing.any((link) => link.todoId == todoId)) return;
    if (await _db.notesDao.getLinkedTodo(todoId) == null) {
      throw const ApiException(404, 'not_found', 'not_found');
    }
    await _db.transaction(() async {
      await _db.notesDao.upsertNoteTodoLink(
        NoteTodoLinksTableCompanion.insert(
          noteId: noteId,
          todoId: todoId,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      await _touchAndEnqueue(noteId);
    });
    _afterLocalWrite();
  }

  Future<void> unlinkTodo(String noteId, String todoId) async {
    await _db.transaction(() async {
      await _db.notesDao.removeNoteTodoLink(noteId, todoId);
      await _touchAndEnqueue(noteId);
    });
    _afterLocalWrite();
  }

  Future<Tag> attachTag(
    String noteId, {
    String? tagId,
    String? name,
    String? color,
  }) async {
    Tag tag;
    if (tagId != null) {
      final row = await _db.todosDao.getTagById(tagId);
      if (row == null) throw const ApiException(404, 'not_found', 'not_found');
      tag = _tagRowToModel(row);
    } else {
      final normalizedName = TagsRepository.normalizeTagName(name ?? '');
      if (normalizedName.isEmpty || normalizedName.length > 64) {
        throw const ApiException(400, 'bad_input', 'Tên tag không hợp lệ');
      }
      tag = await TagsRepository.instance.createLocal(
        name: normalizedName,
        color: jsonColor(color ?? '#6366F1'),
      );
    }

    final ids = (await _db.notesDao.getTagIdsForNote(noteId)).toSet();
    if (ids.contains(tag.id)) return tag;
    if (ids.length >= 20) {
      throw const ApiException(400, 'bad_input', 'Mỗi note tối đa 20 tags');
    }
    ids.add(tag.id);
    await _db.transaction(() async {
      await _db.notesDao.setNoteTags(noteId, ids.toList());
      await _touchAndEnqueue(noteId);
    });
    _afterLocalWrite();
    return tag;
  }

  Future<void> detachTag(String noteId, String tagId) async {
    final ids = (await _db.notesDao.getTagIdsForNote(
      noteId,
    )).where((id) => id != tagId).toList();
    await _db.transaction(() async {
      await _db.notesDao.setNoteTags(noteId, ids);
      await _touchAndEnqueue(noteId);
    });
    _afterLocalWrite();
  }

  Future<void> _cacheServerDetail(NoteWithRelations detail) async {
    final noteId = detail.note.id;
    if (await _hasPendingNote(noteId)) return;
    await _db.transaction(() async {
      for (final tag in detail.tags) {
        await _db.todosDao.upsertTag(
          tagToCompanion(tag, tag.userId ?? _requireUserId()),
        );
      }
      await _db.notesDao.upsertNote(
        noteToCompanion(detail.note, _requireUserId()),
      );
      await _db.notesDao.setNoteTags(
        noteId,
        detail.tags.map((tag) => tag.id).toList(),
      );

      final existingOutgoing = await _db.notesDao.getOutgoingLinks(noteId);
      for (final link in existingOutgoing) {
        await _db.notesDao.removeNoteLink(noteId, link.targetNoteId);
      }
      for (final link in detail.outgoing) {
        await _db.notesDao.upsertNoteLink(
          NoteLinksTableCompanion.insert(
            id: link.id,
            sourceNoteId: link.sourceNoteId,
            targetNoteId: link.targetNoteId,
            label: Value(link.label),
            createdAt: link.createdAt.toUtc().toIso8601String(),
            updatedAt: link.createdAt.toUtc().toIso8601String(),
          ),
        );
      }

      final existingTodos = await _db.notesDao.getTodoLinksForNote(noteId);
      for (final link in existingTodos) {
        await _db.notesDao.removeNoteTodoLink(noteId, link.todoId);
      }
      for (final todo in detail.todos) {
        await _db.notesDao.upsertNoteTodoLink(
          NoteTodoLinksTableCompanion.insert(
            noteId: noteId,
            todoId: todo.id,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
      }
    });
    NoteLocalEvents.instance.notifyChanged();
  }

  Future<void> _touchAndEnqueue(String noteId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(_db.notesTable)..where((note) => note.id.equals(noteId)))
        .write(NotesTableCompanion(updatedAt: Value(now)));
    await _enqueueStoredNote(noteId, operation: 'update');
  }

  Future<void> _enqueueStoredNote(
    String noteId, {
    required String operation,
  }) async {
    final row = await _db.notesDao.getNoteByIdIncludingDeleted(noteId);
    if (row == null) return;
    final tagIds = await _db.notesDao.getTagIdsForNote(noteId);
    final links = (await _db.notesDao.getOutgoingLinks(noteId))
        .map(
          (link) => <String, dynamic>{
            'target_note_id': link.targetNoteId,
            if (link.label != null) 'label': link.label,
          },
        )
        .toList();
    final todoIds = (await _db.notesDao.getTodoLinksForNote(
      noteId,
    )).map((link) => link.todoId).toList();
    await _db.syncDao.enqueueSyncOp(
      userId: _requireUserId(),
      entityType: 'note',
      entityId: noteId,
      operation: operation,
      payload: SyncPayload.encode(
        SyncPayload.fromNote(row, tagIds, links, todoIds),
      ),
    );
  }

  Future<bool> _hasPendingNote(String id) async {
    return await _db.syncDao.getPendingForEntity(
          'note',
          id,
          userId: _requireUserId(),
        ) !=
        null;
  }

  Note _noteRowToModel(NoteRow row) {
    return Note.fromJson({
      'id': row.id,
      'user_id': row.userId,
      'title': row.title,
      'type': row.type,
      'body': row.body,
      'cornell_cue': row.cornellCue,
      'cornell_summary': row.cornellSummary,
      'content_format': row.contentFormat,
      'body_delta': _decodeStoredDelta(row.bodyDelta),
      'cornell_cue_delta': _decodeStoredDelta(row.cornellCueDelta),
      'cornell_summary_delta': _decodeStoredDelta(row.cornellSummaryDelta),
      'is_pinned': row.isPinned,
      'created_at': row.createdAt,
      'updated_at': row.updatedAt,
      'deleted_at': row.deletedAt,
    });
  }

  Tag _tagRowToModel(TagRow row) {
    return Tag(
      id: row.id,
      userId: row.userId,
      name: row.name,
      color: jsonColor(row.color),
      createdAt: jsonDateNullable(row.createdAt),
      updatedAt: jsonDateNullable(row.updatedAt),
      deletedAt: jsonDateNullable(row.deletedAt),
    );
  }

  static Map<String, dynamic>? _decodeStoredDelta(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return sanitizeNoteDelta(jsonDecode(value));
    } catch (_) {
      return null;
    }
  }

  static String _normalizeTitle(String value) {
    final result = value.trim().isEmpty ? '(Không tiêu đề)' : value.trim();
    if (result.length > 500) {
      throw const ApiException(400, 'bad_input', 'Tiêu đề tối đa 500 ký tự');
    }
    return result;
  }

  static String? _nullableText(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static void _validateNote(Note note) {
    if (note.title.trim().isEmpty || note.title.length > 500) {
      throw const ApiException(400, 'bad_input', 'Tiêu đề không hợp lệ');
    }
    if ((note.body?.length ?? 0) > 100000) {
      throw const ApiException(400, 'bad_input', 'Nội dung quá dài');
    }
    if ((note.cornellCue?.length ?? 0) > 10000) {
      throw const ApiException(400, 'bad_input', 'Cues quá dài');
    }
    if ((note.cornellSummary?.length ?? 0) > 10000) {
      throw const ApiException(400, 'bad_input', 'Summary quá dài');
    }
    for (final delta in [
      note.bodyDelta,
      note.cornellCueDelta,
      note.cornellSummaryDelta,
    ]) {
      if (!noteDeltaContainsOnlyInsertOperations(delta)) {
        throw const ApiException(400, 'bad_input', 'Quill Delta không hợp lệ');
      }
    }
  }

  String _requireUserId() {
    final userId = _userId;
    if (userId.isEmpty) {
      throw StateError('Authenticated user id is required for Notes');
    }
    return userId;
  }

  void _afterLocalWrite() {
    NoteLocalEvents.instance.notifyChanged();
    ConnectivitySync.instance.scheduleWriteSync();
  }
}
