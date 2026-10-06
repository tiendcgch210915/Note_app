import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/data/local/database.dart';
import 'package:todonote/data/notes_repository.dart';
import 'package:todonote/models/note.dart';
import 'package:todonote/screens/notes/note_detail_screen.dart';
import 'package:todonote/sync/connectivity_sync.dart';
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
  testWidgets('detail focuses note content without relation sections', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = NotesRepository.forTesting(db, userId: 'user-1');
    addTearDown(() async {
      ConnectivitySync.instance.cancelPending();
      await db.close();
    });

    final detail = await repository.create(
      title: 'Một note',
      type: NoteType.free,
      body: 'Nội dung cũ',
    );
    ConnectivitySync.instance.cancelPending();

    await tester.pumpWidget(
      _app(NoteDetailScreen(noteId: detail.note.id, repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Một note'), findsWidgets);
    expect(find.text('Tags'), findsNothing);
    expect(find.text('Liên kết'), findsNothing);
    expect(find.text('Todos liên quan'), findsNothing);
    expect(find.textContaining('backlink', findRichText: true), findsNothing);

    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(find.byType(NoteQuillToolbar), findsOneWidget);
    expect(find.byTooltip('Hoàn tác'), findsOneWidget);
    expect(find.byTooltip('Làm lại'), findsOneWidget);
    expect(find.byTooltip('Liên kết'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
