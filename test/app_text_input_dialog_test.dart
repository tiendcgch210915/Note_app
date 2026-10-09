import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/widgets/app_sheet.dart';

void main() {
  /// Mở dialog từ một nút và ghi lại giá trị nó trả về.
  Future<ValueNotifier<Object?>> pumpHost(
    WidgetTester tester, {
    String initialText = '',
    String cancelLabel = 'Hủy',
    int? maxLength,
  }) async {
    final result = ValueNotifier<Object?>('chưa đóng');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result.value = await showAppTextInputDialog(
                  context,
                  title: 'Tiêu đề',
                  hintText: 'Gợi ý',
                  initialText: initialText,
                  confirmLabel: 'Đồng ý',
                  cancelLabel: cancelLabel,
                  maxLength: maxLength,
                );
              },
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('confirm returns the trimmed text and closes cleanly', (
    tester,
  ) async {
    final result = await pumpHost(tester);

    await tester.enterText(find.byType(TextField), '  Bước 1  ');
    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result.value, 'Bước 1');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancel returns null and closes cleanly', (tester) async {
    final result = await pumpHost(tester, cancelLabel: 'Bỏ qua');

    await tester.enterText(find.byType(TextField), 'bỏ');
    await tester.tap(find.text('Bỏ qua'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result.value, isNull);
  });

  testWidgets('the keyboard done action submits a single-line dialog', (
    tester,
  ) async {
    final result = await pumpHost(tester);

    await tester.enterText(find.byType(TextField), 'Enter');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result.value, 'Enter');
  });

  testWidgets('shows the initial text and confirming empty returns empty', (
    tester,
  ) async {
    final result = await pumpHost(tester, initialText: 'Cũ');
    expect(find.widgetWithText(TextField, 'Cũ'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result.value, '');
  });

  testWidgets('maxLength is enforced', (tester) async {
    await pumpHost(tester, maxLength: 5);

    await tester.enterText(find.byType(TextField), '1234567890');

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '12345');
  });
}
