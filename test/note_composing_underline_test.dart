import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/widgets/note_quill_editor.dart';
import 'package:todonote/widgets/note_text_editing_controller.dart';

void main() {
  testWidgets('note title composing text renders without underline', (
    tester,
  ) async {
    final controller = NoteTextEditingController();
    controller.value = const TextEditingValue(
      text: 'dang nhap',
      selection: TextSelection.collapsed(offset: 8),
      composing: TextRange(start: 0, end: 4),
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final context = tester.element(find.byType(SizedBox));
    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(color: Colors.black),
      withComposing: true,
    );

    expect(span.text, 'dang nhap');
    expect(span.style?.decoration, isNull);
    expect(span.children, isNull);
  });

  testWidgets('note quill composing underline is stripped from normal text', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final context = tester.element(find.byType(SizedBox));

    final span = buildNoteQuillTextSpan(
      context,
      _FakeQuillNode(),
      0,
      'dang',
      const TextStyle(decoration: TextDecoration.underline),
      null,
    );

    expect(span.style?.decoration, TextDecoration.none);
  });

  testWidgets('note quill keeps real underline formatting', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final context = tester.element(find.byType(SizedBox));

    final span = buildNoteQuillTextSpan(
      context,
      _FakeQuillNode({Attribute.underline.key: Attribute.underline}),
      0,
      'dang',
      const TextStyle(decoration: TextDecoration.underline),
      null,
    );

    expect(span.style?.decoration, TextDecoration.underline);
  });

  testWidgets('checked note checklist text is muted and struck through', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final context = tester.element(find.byType(SizedBox));

    final span = buildNoteQuillTextSpan(
      context,
      _FakeQuillNode(const {}, {Attribute.list.key: Attribute.checked}),
      0,
      'Hoàn thành rồi',
      const TextStyle(color: Colors.black),
      null,
    );

    expect(span.style?.decoration, TextDecoration.lineThrough);
    expect(span.style?.color, isNot(Colors.black));
  });

  testWidgets('checked note checklist custom line style is completion style', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final context = tester.element(find.byType(SizedBox));

    final checked = buildNoteQuillCustomStyle(context, Attribute.checked);
    final unchecked = buildNoteQuillCustomStyle(context, Attribute.unchecked);

    expect(checked.decoration, TextDecoration.lineThrough);
    expect(checked.color, isNotNull);
    expect(unchecked.decoration, isNull);
    expect(unchecked.color, isNull);
  });

  test('note inline links preserve arbitrary annotation text', () {
    expect(normalizeNoteInlineLink('bỏ rơi; từ bỏ'), 'bỏ rơi; từ bỏ');
    expect(
      normalizeNoteInlineLink('  synonym: leave, quit  '),
      'synonym: leave, quit',
    );
    expect(
      normalizeNoteInlineLink('https://example.com'),
      'https://example.com',
    );
    expect(normalizeNoteInlineLink('   '), isNull);
    expect(isHttpUrl('https://example.com'), isTrue);
    expect(isHttpUrl('http://example.com/path'), isTrue);
    expect(isHttpUrl('example.com'), isFalse);
    expect(isHttpUrl('bỏ rơi; từ bỏ'), isFalse);
  });

  testWidgets('non-url inline link tap shows annotation text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              handleNoteInlineLinkTap(context, 'nghĩa tiếng Việt: từ bỏ'),
            ),
            child: const Text('Mở'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();

    expect(find.text('Liên kết'), findsOneWidget);
    expect(find.text('nghĩa tiếng Việt: từ bỏ'), findsOneWidget);

    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
  });
}

class _FakeQuillNode {
  _FakeQuillNode([
    Map<String, dynamic> attributes = const {},
    Map<String, dynamic> parentAttributes = const {},
  ]) : style = _FakeQuillStyle(attributes),
       parent = _FakeQuillNodeParent(parentAttributes);

  final _FakeQuillStyle style;
  final _FakeQuillNodeParent parent;
}

class _FakeQuillNodeParent {
  const _FakeQuillNodeParent(this.attributes);

  final Map<String, dynamic> attributes;

  _FakeQuillStyle get style => _FakeQuillStyle(attributes);
}

class _FakeQuillStyle {
  const _FakeQuillStyle(this.attributes);

  final Map<String, dynamic> attributes;
}
