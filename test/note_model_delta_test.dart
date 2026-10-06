import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/note.dart';
import 'package:todonote/utils/note_delta_utils.dart';

void main() {
  const createdAt = '2026-06-26T08:00:00.000Z';

  Map<String, dynamic> baseJson() => {
    'id': 'note-1',
    'user_id': 'user-1',
    'title': 'Bài học',
    'type': 'cornell',
    'body': 'Nội dung chính',
    'is_pinned': false,
    'created_at': createdAt,
    'updated_at': createdAt,
    'deleted_at': null,
  };

  test('parses free note', () {
    final note = Note.fromJson({
      ...baseJson(),
      'type': 'free',
      'body': 'Ý tưởng',
    });

    expect(note.type, NoteType.free);
    expect(note.body, 'Ý tưởng');
    expect(note.cornellCue, isNull);
  });

  test('parses full Cornell note and Delta objects', () {
    final note = Note.fromJson({
      ...baseJson(),
      'cornell_cue': 'Câu hỏi',
      'cornell_summary': 'Tóm tắt',
      'content_format': noteContentFormatQuill,
      'body_delta': {
        'ops': [
          {
            'insert': 'Nội dung\n',
            'attributes': {'bold': true},
          },
        ],
      },
      'cornell_cue_delta': {
        'ops': [
          {'insert': 'Câu hỏi\n'},
        ],
      },
      'cornell_summary_delta': {
        'ops': [
          {'insert': 'Tóm tắt\n'},
        ],
      },
    });

    expect(note.type, NoteType.cornell);
    expect(note.bodyDelta?['ops'], hasLength(1));
    expect(note.cornellCueDelta, isNotNull);
    expect(note.cornellSummaryDelta, isNotNull);
  });

  test('Cornell with body only accepts null optional sections', () {
    final note = Note.fromJson({
      ...baseJson(),
      'cornell_cue': null,
      'cornell_summary': null,
      'cornell_cue_delta': null,
      'cornell_summary_delta': null,
    });

    expect(note.body, 'Nội dung chính');
    expect(note.cornellCue, isNull);
    expect(note.cornellSummary, isNull);
  });

  test('Cornell preview prefers summary then notes then cues', () {
    final full = Note.fromJson({
      ...baseJson(),
      'cornell_cue': 'Cue',
      'cornell_summary': 'Summary',
    });
    final bodyOnly = Note.fromJson({
      ...baseJson(),
      'cornell_cue': 'Cue',
      'cornell_summary': null,
    });

    expect(full.previewBody, 'Summary');
    expect(bodyOnly.previewBody, 'Nội dung chính');
  });

  test('malformed or non-insert Delta falls back safely', () {
    final note = Note.fromJson({
      ...baseJson(),
      'content_format': noteContentFormatQuill,
      'body_delta': {
        'ops': [
          {'retain': 4},
          {'delete': 2},
          {'insert': 'Hợp lệ'},
        ],
      },
    });

    expect(note.bodyDelta, {
      'ops': [
        {'insert': 'Hợp lệ'},
        {'insert': '\n'},
      ],
    });
  });
}
