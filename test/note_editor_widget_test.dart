import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/notes_repository.dart';
import 'package:todonote/models/note.dart';
import 'package:todonote/screens/notes/note_editor_screen.dart';
import 'package:todonote/sync/connectivity_sync.dart';
import 'package:todonote/widgets/cornell_note_layout.dart';
import 'package:todonote/widgets/note_quill_editor.dart';

Widget _app(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: const [Locale('vi'), Locale('en')],
    home: child,
  );
}

void main() {
  test('note editor reserves extra scroll room above mobile keyboard', () {
    final padding = noteKeyboardAwareBottomPadding(
      viewportSize: const Size(390, 820),
      keyboardInset: 320,
      editorFocused: true,
      restingPadding: 112,
    );

    expect(padding, greaterThan(400));
    expect(
      noteKeyboardAwareBottomPadding(
        viewportSize: const Size(390, 820),
        keyboardInset: 320,
        editorFocused: false,
        restingPadding: 80,
      ),
      80,
    );
  });

  test('note editor scroll offset reveals the active caret', () {
    expect(
      noteScrollOffsetForCaret(
        currentOffset: 120,
        minOffset: 0,
        maxOffset: 600,
        caretTop: 560,
        caretBottom: 584,
        visibleTop: 100,
        visibleBottom: 520,
      ),
      greaterThan(180),
    );
    expect(
      noteScrollOffsetForCaret(
        currentOffset: 120,
        minOffset: 0,
        maxOffset: 600,
        caretTop: 70,
        caretBottom: 94,
        visibleTop: 100,
        visibleBottom: 520,
      ),
      lessThan(120),
    );
    expect(
      noteScrollOffsetForCaret(
        currentOffset: 120,
        minOffset: 0,
        maxOffset: 600,
        caretTop: 220,
        caretBottom: 244,
        visibleTop: 100,
        visibleBottom: 520,
      ),
      120,
    );
  });

  testWidgets('new note exposes explicit Free and Cornell choices', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const NoteEditorScreen()));
    await tester.pump();

    expect(find.text('Ghi chú thường'), findsOneWidget);
    expect(find.text('Cornell'), findsOneWidget);
    expect(find.byType(QuillEditor), findsOneWidget);

    await tester.tap(find.text('Cornell'));
    await tester.pumpAndSettle();

    expect(find.byType(QuillEditor), findsNWidgets(3));
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Cues'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
  });

  testWidgets('Cornell to Free asks before discarding optional sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const NoteEditorScreen(initialType: NoteType.cornell)),
    );
    await tester.pump();

    await tester.tap(find.text('Ghi chú thường'));
    await tester.pumpAndSettle();

    expect(
      find.text('Chuyển sang ghi chú thường sẽ xóa cột gợi ý và phần tóm tắt.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.byType(QuillEditor), findsNWidgets(3));
  });

  testWidgets('wide Cornell layout is approximately 30/70 with full summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(20),
            child: CornellNoteLayout(
              notes: SizedBox(height: 320),
              cues: SizedBox(height: 320),
              summary: SizedBox(height: 120),
            ),
          ),
        ),
      ),
    );

    final cues = tester.getSize(
      find.byKey(const ValueKey('cornell-cues-section')),
    );
    final notes = tester.getSize(
      find.byKey(const ValueKey('cornell-notes-section')),
    );
    final summary = tester.getSize(
      find.byKey(const ValueKey('cornell-summary-section')),
    );

    expect(notes.width / (notes.width + cues.width), closeTo(0.7, 0.04));
    expect(summary.width, greaterThan(900));
  });

  testWidgets('narrow Cornell layout keeps Notes then Cues then Summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: SingleChildScrollView(
            child: CornellNoteLayout(
              notes: SizedBox(height: 220),
              cues: SizedBox(height: 180),
              summary: SizedBox(height: 140),
            ),
          ),
        ),
      ),
    );

    final notesY = tester
        .getTopLeft(find.byKey(const ValueKey('cornell-notes-section')))
        .dy;
    final cuesY = tester
        .getTopLeft(find.byKey(const ValueKey('cornell-cues-section')))
        .dy;
    final summaryY = tester
        .getTopLeft(find.byKey(const ValueKey('cornell-summary-section')))
        .dy;

    expect(notesY, lessThan(cuesY));
    expect(cuesY, lessThan(summaryY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('autosave coalesces rapid edits into one local create', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = NotesRepository.forTesting(db, userId: 'user-1');
    addTearDown(() async {
      ConnectivitySync.instance.cancelPending();
      await db.close();
    });
    await tester.pumpWidget(_app(NoteEditorScreen(repository: repository)));
    await tester.pump();

    final title = find.byType(TextField).first;
    await tester.enterText(title, 'B');
    await tester.enterText(title, 'Bài');
    await tester.enterText(title, 'Bài học');
    await tester.pump(const Duration(milliseconds: 1100));

    final notes = await repository.listLocal();
    final queue = await db.syncDao.getRowsForUser(userId: 'user-1');
    expect(notes, hasLength(1));
    expect(notes.single.title, 'Bài học');
    expect(queue, hasLength(1));
    expect(queue.single.operation, 'create');
    ConnectivitySync.instance.cancelPending();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('back navigation flushes a pending local save', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = NotesRepository.forTesting(db, userId: 'user-1');
    addTearDown(() async {
      ConnectivitySync.instance.cancelPending();
      await db.close();
    });
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NoteEditorScreen(repository: repository),
                ),
              ),
              child: const Text('Mở editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Flush khi thoát');

    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    ConnectivitySync.instance.cancelPending();

    final notes = await repository.listLocal();
    expect(notes, hasLength(1));
    expect(notes.single.title, 'Flush khi thoát');
    expect(find.text('Mở editor'), findsOneWidget);
  });
}
