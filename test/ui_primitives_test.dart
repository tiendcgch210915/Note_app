import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/theme/app_theme.dart';
import 'package:todonote/widgets/app_state_views.dart';
import 'package:todonote/widgets/app_surface.dart';
import 'package:todonote/widgets/empty_state.dart';
import 'package:todonote/widgets/primary_button.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('PrimaryButton', () {
    testWidgets('shows the label and fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(PrimaryButton(label: 'Lưu', onPressed: () => taps++)),
      );

      expect(find.text('Lưu'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('swallows taps and shows a spinner while loading', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          PrimaryButton(label: 'Lưu', loading: true, onPressed: () => taps++),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('Lưu'), findsNothing);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(_host(const PrimaryButton(label: 'Lưu')));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('can be rendered in every variant', (tester) async {
      for (final variant in PrimaryButtonVariant.values) {
        await tester.pumpWidget(
          _host(
            PrimaryButton(
              label: variant.name,
              variant: variant,
              onPressed: () {},
            ),
            theme: AppTheme.dark(),
          ),
        );
        expect(find.text(variant.name), findsOneWidget);
      }
    });
  });

  group('EmptyState', () {
    testWidgets('renders title, subtitle and a working action', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          EmptyState(
            title: 'Trống',
            subtitle: 'Hãy thêm mục đầu tiên',
            buttonLabel: 'Thêm',
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trống'), findsOneWidget);
      expect(find.text('Hãy thêm mục đầu tiên'), findsOneWidget);
      await tester.tap(find.text('Thêm'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('omits the button when there is no label', (tester) async {
      await tester.pumpWidget(_host(const EmptyState(title: 'Trống')));
      await tester.pumpAndSettle();

      expect(find.byType(PrimaryButton), findsNothing);
    });
  });

  group('AppErrorState', () {
    testWidgets('offers a retry action', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _host(AppErrorState(message: 'Mất kết nối', onRetry: () => retries++)),
      );

      expect(find.text('Mất kết nối'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      expect(retries, 1);
    });
  });

  group('AppSurface', () {
    testWidgets('is tappable and has no ink ripple of its own', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          AppSurface(
            onTap: () => taps++,
            padding: const EdgeInsets.all(16),
            child: const Text('Thẻ'),
          ),
        ),
      );

      await tester.tap(find.text('Thẻ'));
      await tester.pump();
      expect(taps, 1);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('is passive without callbacks', (tester) async {
      await tester.pumpWidget(
        _host(const AppSurface(child: SizedBox(width: 40, height: 40))),
      );

      expect(find.byType(GestureDetector), findsNothing);
    });
  });
}
