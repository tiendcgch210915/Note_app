import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/widgets/app_list_section.dart';

void main() {
  testWidgets('renders header, rows, dividers and handles taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppListSection(
              header: 'Tài khoản',
              footer: 'Chú thích',
              children: [
                AppListTile(
                  icon: Icons.person,
                  title: 'Hồ sơ',
                  value: 'An',
                  onTap: () => taps++,
                ),
                const AppListTile(title: 'Phiên bản', value: '1.0'),
                AppListTile(
                  title: 'Đăng xuất',
                  destructive: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('TÀI KHOẢN'), findsOneWidget);
    expect(find.text('Chú thích'), findsOneWidget);
    expect(find.text('Hồ sơ'), findsOneWidget);
    expect(find.text('An'), findsOneWidget);
    // 3 hàng => 2 đường kẻ ngăn cách.
    expect(find.byType(Divider), findsNWidgets(2));
    // Chỉ hàng có onTap mới có mũi tên.
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));

    await tester.tap(find.text('Hồ sơ'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('non-interactive tile has no chevron and ignores taps', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppListSection(children: [AppListTile(title: 'Chỉ đọc')]),
        ),
      ),
    );

    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
  });
}
