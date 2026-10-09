import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/widgets/app_segmented_control.dart';

void main() {
  testWidgets('shows every label and reports taps on another segment', (
    tester,
  ) async {
    var value = 'a';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsets.all(16),
              child: AppSegmentedControl<String>(
                value: value,
                onChanged: (v) => setState(() => value = v),
                segments: const [
                  AppSegment(value: 'a', label: 'Một'),
                  AppSegment(value: 'b', label: 'Hai', icon: Icons.star),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Một'), findsOneWidget);
    expect(find.text('Hai'), findsOneWidget);

    await tester.tap(find.text('Hai'));
    await tester.pumpAndSettle();
    expect(value, 'b');

    // Chạm lại đoạn đang chọn không phát sự kiện mới.
    await tester.tap(find.text('Hai'));
    await tester.pumpAndSettle();
    expect(value, 'b');
  });

  testWidgets('stretches to the available width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 300,
              child: AppSegmentedControl<int>(
                value: 1,
                onChanged: (_) {},
                segments: const [
                  AppSegment(value: 1, label: 'X'),
                  AppSegment(value: 2, label: 'Y'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(AppSegmentedControl<int>));
    expect(size.width, closeTo(300, 6));
  });
}
