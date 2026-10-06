import 'dart:convert';

import '../utils/json_utils.dart';
import '../utils/note_delta_utils.dart';
import 'tag.dart';

enum NoteType {
  free,
  cornell;

  String get label {
    switch (this) {
      case NoteType.free:
        return 'Ghi chú thường';
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
  final String? userId;
  final String title;
  final NoteType type;
  final String? body;
  final String? cornellCue;
  final String? cornellSummary;
  final String contentFormat;
  final Map<String, dynamic>? bodyDelta;
  final Map<String, dynamic>? cornellCueDelta;
  final Map<String, dynamic>? cornellSummaryDelta;
  final bool isPinned;
  final List<Tag> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Note({
    required this.id,
    this.userId,
    required this.title,
    this.type = NoteType.free,
    this.body,
    this.cornellCue,
    this.cornellSummary,
    this.contentFormat = 'plain',
    this.bodyDelta,
    this.cornellCueDelta,
    this.cornellSummaryDelta,
    this.isPinned = false,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      title: json['title'] as String,
      type: NoteType.parse(json['type'] as String? ?? 'free'),
      body: json['body'] as String?,
      cornellCue: json['cornell_cue'] as String?,
      cornellSummary: json['cornell_summary'] as String?,
      contentFormat: json['content_format'] == noteContentFormatQuill
          ? noteContentFormatQuill
          : noteContentFormatPlain,
      bodyDelta: _parseJsonObject(json['body_delta']),
      cornellCueDelta: _parseJsonObject(json['cornell_cue_delta']),
      cornellSummaryDelta: _parseJsonObject(json['cornell_summary_delta']),
      isPinned: jsonBool(json['is_pinned']),
      tags: const [], // list response không trả tags inline; getDetail mới có
      createdAt: jsonDate(json['created_at'] as String),
      updatedAt: jsonDate(json['updated_at'] as String),
      deletedAt: jsonDateNullable(json['deleted_at'] as String?),
    );
  }

  static Map<String, dynamic>? _parseJsonObject(dynamic value) {
    if (value == null) return null;
    if (value is Map) return sanitizeNoteDelta(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return sanitizeNoteDelta(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Body cho POST /notes (Free or Cornell). Caller cung cấp đầy đủ field bắt buộc.
  static Map<String, dynamic> createBody({
    required String title,
    required NoteType type,
    String? body,
    String? cornellCue,
    String? cornellSummary,
    Map<String, dynamic>? bodyDelta,
    Map<String, dynamic>? cornellCueDelta,
    Map<String, dynamic>? cornellSummaryDelta,
    String contentFormat = noteContentFormatPlain,
    bool isPinned = false,
    List<String> tags = const [],
  }) {
    return {
      'type': type.backendValue,
      'title': title,
      if (body != null) 'body': body,
      'body_delta': sanitizeNoteDelta(bodyDelta),
      'content_format': contentFormat,
      if (type == NoteType.cornell) ...{
        'cornell_cue': cornellCue,
        'cornell_summary': cornellSummary,
        'cornell_cue_delta': sanitizeNoteDelta(cornellCueDelta),
        'cornell_summary_delta': sanitizeNoteDelta(cornellSummaryDelta),
      },
      'is_pinned': isPinned,
      if (tags.isNotEmpty) 'tags': tags,
    };
  }

  /// Preview body cho card list.
  String get previewBody {
    final raw = type == NoteType.cornell
        ? _firstNonEmpty(cornellSummary, body, cornellCue)
        : body ?? '';
    if (raw.length <= 120) return raw;
    return '${raw.substring(0, 120)}…';
  }

  Note copyWith({
    String? title,
    NoteType? type,
    String? body,
    bool clearBody = false,
    String? cornellCue,
    bool clearCornellCue = false,
    String? cornellSummary,
    bool clearCornellSummary = false,
    String? contentFormat,
    Map<String, dynamic>? bodyDelta,
    bool clearBodyDelta = false,
    Map<String, dynamic>? cornellCueDelta,
    bool clearCornellCueDelta = false,
    Map<String, dynamic>? cornellSummaryDelta,
    bool clearCornellSummaryDelta = false,
    bool? isPinned,
    List<Tag>? tags,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return Note(
      id: id,
      userId: userId,
      title: title ?? this.title,
      type: type ?? this.type,
      body: clearBody ? null : body ?? this.body,
      cornellCue: clearCornellCue ? null : cornellCue ?? this.cornellCue,
      cornellSummary: clearCornellSummary
          ? null
          : cornellSummary ?? this.cornellSummary,
      contentFormat: contentFormat ?? this.contentFormat,
      bodyDelta: clearBodyDelta ? null : bodyDelta ?? this.bodyDelta,
      cornellCueDelta: clearCornellCueDelta
          ? null
          : cornellCueDelta ?? this.cornellCueDelta,
      cornellSummaryDelta: clearCornellSummaryDelta
          ? null
          : cornellSummaryDelta ?? this.cornellSummaryDelta,
      isPinned: isPinned ?? this.isPinned,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  static String _firstNonEmpty(String? first, String? second, String? third) {
    for (final value in [first, second, third]) {
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return '';
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
