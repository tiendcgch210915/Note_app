import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/utils/note_delta_utils.dart';

void main() {
  test('legacy plain text hydrates and round-trips as insert-only Delta', () {
    final document = noteDocumentFrom(plainText: 'Nội dung cũ');
    final delta = noteDeltaFromDocument(document);

    expect(notePlainTextFromDocument(document), 'Nội dung cũ');
    expect(noteDeltaContainsOnlyInsertOperations(delta), isTrue);
    expect(delta, {
      'ops': [
        {'insert': 'Nội dung cũ\n'},
      ],
    });
  });

  test('formatted Delta round-trips without Markdown conversion', () {
    final source = {
      'ops': [
        {
          'insert': 'Đậm',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ],
    };
    final document = noteDocumentFrom(delta: source);

    expect(noteDeltaFromDocument(document), source);
    expect(notePlainTextFromDocument(document), 'Đậm');
  });

  test('sanitize removes retain delete embeds and unsupported attributes', () {
    final sanitized = sanitizeNoteDelta({
      'ops': [
        {'retain': 2},
        {'delete': 1},
        {
          'insert': {'image': 'x'},
        },
        {
          'insert': 'Text',
          'attributes': {'bold': true, 'color': '#fff'},
        },
      ],
    });

    expect(sanitized, {
      'ops': [
        {
          'insert': 'Text',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ],
    });
  });

  test(
    'sanitize preserves arbitrary link text and removes empty links only',
    () {
      final sanitized = sanitizeNoteDelta({
        'ops': [
          {
            'insert': 'abandon',
            'attributes': {'bold': true, 'link': '  bỏ rơi; từ bỏ  '},
          },
          {
            'insert': 'empty',
            'attributes': {'bold': true, 'link': '   '},
          },
          {
            'insert': 'false',
            'attributes': {'italic': true, 'link': false},
          },
          {'insert': '\n'},
        ],
      });

      expect(sanitized, {
        'ops': [
          {
            'insert': 'abandon',
            'attributes': {'bold': true, 'link': '  bỏ rơi; từ bỏ  '},
          },
          {
            'insert': 'empty',
            'attributes': {'bold': true},
          },
          {
            'insert': 'false',
            'attributes': {'italic': true},
          },
          {'insert': '\n'},
        ],
      });
    },
  );

  test('removing inline link keeps other text attributes', () {
    final document = noteDocumentFrom(
      delta: const {
        'ops': [
          {
            'insert': 'abandon',
            'attributes': {'bold': true, 'link': 'bỏ rơi; từ bỏ'},
          },
          {'insert': '\n'},
        ],
      },
    );
    final controller = QuillController(
      document: document,
      selection: const TextSelection(baseOffset: 0, extentOffset: 7),
    );

    controller.formatText(0, 7, Attribute.link);

    expect(noteDeltaFromDocument(controller.document), {
      'ops': [
        {
          'insert': 'abandon',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ],
    });
  });
}
