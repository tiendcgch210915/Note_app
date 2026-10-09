import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/habit.dart';
import 'package:todonote/theme/app_theme.dart';
import 'package:todonote/widgets/habit_card.dart';

/// Thư mục font Roboto đi kèm Flutter SDK (để đo chữ bằng số liệu thật thay vì
/// font Ahem của flutter_test vốn rộng gấp ~2 lần). Null nếu không tìm thấy.
Directory? _robotoDir() {
  final candidates = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) candidates.add(root);
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    candidates.add(dir.path);
    dir = dir.parent;
  }
  for (final base in candidates) {
    final fonts = Directory('$base/bin/cache/artifacts/material_fonts');
    if (fonts.existsSync()) return fonts;
  }
  return null;
}

Habit _habit(int streak) => Habit(
  id: 'h',
  title: 'Đọc sách',
  iconName: 'book',
  icon: Icons.menu_book,
  color: Colors.green,
  startDate: DateTime(2026, 1, 1),
  currentStreak: streak,
  longestStreak: streak + 3,
);

void main() {
  final fonts = _robotoDir();

  testWidgets(
    'HabitCard hiện đủ cỡ số ngày streak 1-2 chữ số trên màn hình 360dp',
    (tester) async {
      final loader = FontLoader('Roboto');
      await tester.runAsync(() async {
        for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf']) {
          final bytes = await File('${fonts!.path}/$name').readAsBytes();
          loader.addFont(
            Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
          );
        }
        await loader.load();
      });

      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // (chiều rộng màn hình, streak, tỉ lệ thu nhỏ tối thiểu chấp nhận được)
      const cases = <(double, int, double)>[
        (360, 0, 0.99),
        (360, 9, 0.99),
        (360, 10, 0.99),
        (360, 99, 0.99),
        (360, 100, 0.9),
        (360, 999, 0.75),
        (320, 10, 0.9),
        (320, 99, 0.9),
        (320, 100, 0.75),
        (393, 99, 0.99),
        (411, 100, 0.95),
      ];
      for (final (width, streak, minScale) in cases) {
        tester.view.physicalSize = Size(width, 800);
        // Đúng công thức ô lưới 3 cột của HabitsListScreen.
        final cellWidth = (width - 32 - 16) / 3;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: cellWidth,
                  height: 150,
                  child: HabitCard(habit: _habit(streak)),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final number = find.text('$streak');
        final unit = find.text('ngày');
        expect(number, findsOneWidget, reason: 'w=$width streak=$streak');
        expect(unit, findsOneWidget, reason: 'w=$width streak=$streak');

        final shown = tester.getRect(number).width;
        final natural = tester.getSize(number).width;
        expect(
          shown / natural,
          greaterThanOrEqualTo(minScale),
          reason:
              'streak $streak ở màn $width bị thu nhỏ còn '
              '${(100 * shown / natural).round()}%',
        );
        // Số và chữ "ngày" nằm gọn trong thẻ, không bị đẩy ra ngoài.
        final card = tester.getRect(find.byType(HabitCard));
        expect(card.contains(tester.getRect(number).topLeft), isTrue);
        expect(card.contains(tester.getRect(unit).bottomRight), isTrue);
        expect(tester.takeException(), isNull);
      }
    },
    // Không tìm thấy font Roboto của Flutter SDK thì bỏ qua.
    skip: fonts == null,
  );
}
