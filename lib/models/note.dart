import '../utils/json_utils.dart';
import 'tag.dart';

enum NoteType {
  free,
  cornell;

  String get label {
    switch (this) {
      case NoteType.free:
        return 'Tự do';
      case NoteType.cornell:
        return 'Cornell';
    }
  }

  static NoteType parse(String s) {
    switch (s) {
      case 'cornell':
        return NoteType.cornell;
      default:
        return NoteType.free;
    }
  }

  String get backendValue => name; // 'free' or 'cornell'
}

class Note {
  final String id;
  final String title;
  final NoteType type;
  final String? body;
  final String? cornellCue;
  final String? cornellSummary;
  final bool isPinned;
  final List<Tag> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.title,
    this.type = NoteType.free,
    this.body,
    this.cornellCue,
    this.cornellSummary,
    this.isPinned = false,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String,
      type: NoteType.parse(json['type'] as String? ?? 'free'),
      body: json['body'] as String?,
      cornellCue: json['cornell_cue'] as String?,
      cornellSummary: json['cornell_summary'] as String?,
      isPinned: jsonBool(json['is_pinned']),
      tags: const [], // list response không trả tags inline; getDetail mới có
      createdAt: jsonDate(json['created_at'] as String),
      updatedAt: jsonDate(json['updated_at'] as String),
    );
  }

  /// Body cho POST /notes (Free or Cornell). Caller cung cấp đầy đủ field bắt buộc.
  static Map<String, dynamic> createBody({
    required String title,
    required NoteType type,
    String? body,
    String? cornellCue,
    String? cornellSummary,
    bool isPinned = false,
    List<String> tags = const [],
  }) {
    return {
      'type': type.backendValue,
      'title': title,
      if (body != null) 'body': body,
      if (type == NoteType.cornell) ...{
        'cornell_cue': cornellCue,
        'cornell_summary': cornellSummary,
      },
      'is_pinned': isPinned,
      if (tags.isNotEmpty) 'tags': tags,
    };
  }

  /// Preview body cho card list.
  String get previewBody {
    final raw = body ?? cornellSummary ?? cornellCue ?? '';
    if (raw.length <= 120) return raw;
    return '${raw.substring(0, 120)}…';
  }
}

/// Outgoing link — note này link tới note khác.
class OutgoingLink {
  final String id;
  final String sourceNoteId;
  final String targetNoteId;
  final String? label;
  final DateTime createdAt;
  final String targetTitle;

  const OutgoingLink({
    required this.id,
    required this.sourceNoteId,
    required this.targetNoteId,
    this.label,
    required this.createdAt,
    required this.targetTitle,
  });

  factory OutgoingLink.fromJson(Map<String, dynamic> json) {
    return OutgoingLink(
      id: json['id'] as String,
      sourceNoteId: json['source_note_id'] as String,
      targetNoteId: json['target_note_id'] as String,
      label: json['label'] as String?,
      createdAt: jsonDate(json['created_at'] as String),
      targetTitle: json['target_title'] as String? ?? '',
    );
  }
}

/// Incoming link — note khác link tới note này (backlink).
class IncomingLink {
  final String id;
  final String sourceNoteId;
  final String targetNoteId;
  final String? label;
  final DateTime createdAt;
  final String sourceTitle;

  const IncomingLink({
    required this.id,
    required this.sourceNoteId,
    required this.targetNoteId,
    this.label,
    required this.createdAt,
    required this.sourceTitle,
  });

  factory IncomingLink.fromJson(Map<String, dynamic> json) {
    return IncomingLink(
      id: json['id'] as String,
      sourceNoteId: json['source_note_id'] as String,
      targetNoteId: json['target_note_id'] as String,
      label: json['label'] as String?,
      createdAt: jsonDate(json['created_at'] as String),
      sourceTitle: json['source_title'] as String? ?? '',
    );
  }
}

/// Todo nhỏ gọn liên kết với note. Tránh import Todo để không circular.
class LinkedTodo {
  final String id;
  final String title;
  final String status; // 'open' | 'in_progress' | 'done' | 'archived'

  const LinkedTodo({
    required this.id,
    required this.title,
    required this.status,
  });

  factory LinkedTodo.fromJson(Map<String, dynamic> json) {
    return LinkedTodo(
      id: json['id'] as String,
      title: json['title'] as String,
      status: json['status'] as String? ?? 'open',
    );
  }

  bool get isDone => status == 'done';
}

/// Response của F-B3 GET /notes/:id — đủ data render full Zettelkasten view.
class NoteWithRelations {
  final Note note;
  final List<Tag> tags;
  final List<OutgoingLink> outgoing;
  final List<IncomingLink> incoming;
  final List<LinkedTodo> todos;

  const NoteWithRelations({
    required this.note,
    required this.tags,
    required this.outgoing,
    required this.incoming,
    required this.todos,
  });

  factory NoteWithRelations.fromJson(Map<String, dynamic> json) {
    return NoteWithRelations(
      note: Note.fromJson(json['note'] as Map<String, dynamic>),
      tags:
          (json['tags'] as List?)
              ?.map((e) => Tag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      outgoing:
          (json['outgoing'] as List?)
              ?.map((e) => OutgoingLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      incoming:
          (json['incoming'] as List?)
              ?.map((e) => IncomingLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      todos:
          (json['todos'] as List?)
              ?.map((e) => LinkedTodo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
