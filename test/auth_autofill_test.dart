import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/screens/auth/login_screen.dart';
import 'package:todonote/screens/auth/register_screen.dart';

void main() {
  // Android dựng cấu trúc autofill từ đúng payload TextInput.setClient này.
  Future<List<Map<String, dynamic>>> focusFirstFieldAndReadGroup(
    WidgetTester tester,
  ) async {
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    final fields = tester.testTextInput.setClientArgs!['fields'] as List?;
    expect(
      fields,
      isNotNull,
      reason:
          'No AutofillGroup: the password manager only sees the focused '
          'field, so it cannot fill account and password in one tap.',
    );
    return fields!.cast<Map<String, dynamic>>();
  }

  List<String> hintsOf(Map<String, dynamic> field) {
    final autofill = field['autofill'] as Map<String, dynamic>;
    return (autofill['hints'] as List).cast<String>();
  }

  bool isObscured(Map<String, dynamic> field) => field['obscureText'] == true;

  testWidgets('login fields share one autofill group with credential hints', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    final fields = await focusFirstFieldAndReadGroup(tester);

    expect(fields, hasLength(2));
    final account = fields.singleWhere((f) => !isObscured(f));
    final password = fields.singleWhere(isObscured);
    expect(
      hintsOf(account),
      containsAll(<String>[AutofillHints.username, AutofillHints.email]),
    );
    expect(hintsOf(password), contains(AutofillHints.password));
  });

  testWidgets('register fields share one autofill group with credential hints', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));

    final fields = await focusFirstFieldAndReadGroup(tester);

    final email = fields.singleWhere(
      (f) => hintsOf(f).contains(AutofillHints.email),
    );
    final password = fields.singleWhere(isObscured);
    expect(isObscured(email), isFalse);
    // `password` đi kèm để dịch vụ chưa hiểu `newPassword` vẫn nhận ra ô mật khẩu.
    expect(
      hintsOf(password),
      containsAll(<String>[AutofillHints.newPassword, AutofillHints.password]),
    );
  });
}
