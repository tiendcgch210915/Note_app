import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/widgets/pressable.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  double scaleOf(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('shrinks while pressed and restores on release', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        Pressable(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );

    expect(scaleOf(tester), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SizedBox).last),
    );
    await tester.pump();
    expect(scaleOf(tester), lessThan(1));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
    expect(taps, 1);
  });

  testWidgets('restores when the finger drags away (scrolling)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const Pressable(child: SizedBox(width: 100, height: 100))),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SizedBox).last),
    );
    await tester.pump();
    expect(scaleOf(tester), lessThan(1));

    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(scaleOf(tester), 1);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('does nothing when disabled', (tester) async {
    await tester.pumpWidget(
      host(
        const Pressable(
          enabled: false,
          child: SizedBox(width: 100, height: 100),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SizedBox).last),
    );
    await tester.pump();
    expect(scaleOf(tester), 1);
    await gesture.up();
  });
}
