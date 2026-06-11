import '../models/note.dart';
import '../models/tag.dart';
import 'api_client.dart';

/// Repository cho Notes (Group B + C + D + E).
class NotesRepository {
  NotesRepository._();
  static final NotesRepository instance = NotesRepository._();
  final ApiClient _client = ApiClient.instance;

  // ─── F-B2 List ──────────────────────────────────────────────────
  Future<({List<Note> items, String? nextCursor})> list({
    String? cursor,
    int? limit,
    String? q,
    bool? pinned,
    String? type,
  }) async {
    final query = <String, dynamic>{
      if (cursor != null) 'cursor': cursor,
      if (limit != null) 'limit': limit,
      if (q != null && q.isNotEmpty) 'q': q,
      if (pinned != null) 'pinned': pinned,
      if (type != null) 'type': type,
    };
    final resp = await _client.get('/notes', query: query);
    final map = resp as Map<String, dynamic>;
    final items = (map['items'] as List)
        .map((e) => Note.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, nextCursor: map['nextCursor'] as String?);
  }

  // ─── F-B3 Detail ────────────────────────────────────────────────
  Future<NoteWithRelations> getDetail(String id) async {
    final resp = await _client.get('/notes/$id');
    return NoteWithRelations.fromJson(resp as Map<String, dynamic>);
  }

  // ─── F-B1 Create ────────────────────────────────────────────────
  Future<NoteWithRelations> create({
    required String title,
    required NoteType type,
    String? body,
    String? cornellCue,
    String? cornellSummary,
    bool isPinned = false,
    List<String> tags = const [],
  }) async {
    final reqBody = Note.createBody(
      title: title,
      type: type,
      body: body,
      cornellCue: cornellCue,
      cornellSummary: cornellSummary,
      isPinned: isPinned,
      tags: tags,
    );
    final resp = await _client.post('/notes', body: reqBody);
    // POST response chỉ trả { note, tags } chứ không có outgoing/incoming/todos
    final map = resp as Map<String, dynamic>;
    return NoteWithRelations(
      note: Note.fromJson(map['note'] as Map<String, dynamic>),
      tags:
          (map['tags'] as List?)
              ?.map((e) => Tag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      outgoing: const [],
      incoming: const [],
      todos: const [],
    );
  }

  // ─── F-B4 Update ────────────────────────────────────────────────
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
    bool? isPinned,
  }) async {
    final reqBody = <String, dynamic>{
      if (title != null) 'title': title,
      if (type != null) 'type': type.backendValue,
      if (clearBody) 'body': null else if (body != null) 'body': body,
      if (clearCornellCue)
        'cornell_cue': null
      else if (cornellCue != null)
        'cornell_cue': cornellCue,
      if (clearCornellSummary)
        'cornell_summary': null
      else if (cornellSummary != null)
        'cornell_summary': cornellSummary,
      if (isPinned != null) 'is_pinned': isPinned,
    };
    final resp = await _client.patch('/notes/$id', body: reqBody);
    return Note.fromJson(
      (resp as Map<String, dynamic>)['note'] as Map<String, dynamic>,
    );
  }

  // ─── F-B5 Delete ────────────────────────────────────────────────
  Future<void> delete(String id) async {
    await _client.delete('/notes/$id');
  }

  // ─── F-C1 Add link ──────────────────────────────────────────────
  Future<OutgoingLink> addLink(
    String sourceId,
    String targetId, {
    String? label,
  }) async {
    final resp = await _client.post(
      '/notes/$sourceId/links',
      body: {
        'targetId': targetId,
        if (label != null && label.isNotEmpty) 'label': label,
      },
    );
    final linkJson =
        (resp as Map<String, dynamic>)['link'] as Map<String, dynamic>;
    // Backend chỉ trả link, không target_title — set tạm rỗng, caller refetch detail.
    return OutgoingLink(
      id: linkJson['id'] as String,
      sourceNoteId: linkJson['source_note_id'] as String,
      targetNoteId: linkJson['target_note_id'] as String,
      label: linkJson['label'] as String?,
      createdAt: DateTime.parse(linkJson['created_at'] as String),
      targetTitle: '',
    );
  }

  // ─── F-C2 Remove link ───────────────────────────────────────────
  Future<void> removeLink(String sourceId, String targetId) async {
    await _client.delete('/notes/$sourceId/links/$targetId');
  }

  // ─── F-C3 Backlinks ─────────────────────────────────────────────
  Future<List<IncomingLink>> getBacklinks(String id) async {
    final resp = await _client.get('/notes/$id/backlinks');
    final items = (resp as Map<String, dynamic>)['items'] as List;
    return items
        .map((e) => IncomingLink.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── F-D1 Link todo ─────────────────────────────────────────────
  Future<void> linkTodo(String noteId, String todoId) async {
    await _client.post('/notes/$noteId/todo-links', body: {'todoId': todoId});
  }

  // ─── F-D2 Unlink todo ───────────────────────────────────────────
  Future<void> unlinkTodo(String noteId, String todoId) async {
    await _client.delete('/notes/$noteId/todo-links/$todoId');
  }

  // ─── F-E1 Attach tag ────────────────────────────────────────────
  Future<Tag> attachTag(
    String noteId, {
    String? tagId,
    String? name,
    String? color,
  }) async {
    final body = <String, dynamic>{
      if (tagId != null) 'tagId': tagId,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
    };
    final resp = await _client.post('/notes/$noteId/tags', body: body);
    return Tag.fromJson(
      (resp as Map<String, dynamic>)['tag'] as Map<String, dynamic>,
    );
  }

  // ─── F-E2 Detach tag ────────────────────────────────────────────
  Future<void> detachTag(String noteId, String tagId) async {
    await _client.delete('/notes/$noteId/tags/$tagId');
  }
}
