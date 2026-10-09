import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/theme/app_colors.dart';
import 'package:todonote/theme/app_theme.dart';
import 'package:todonote/theme/app_tokens.dart';

void main() {
  for (final entry in {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  }.entries) {
    group('${entry.key} theme', () {
      final theme = entry.value;

      test('uses squircle shapes for dialog, sheet, snackbar and cards', () {
        expect(theme.dialogTheme.shape, isA<RoundedSuperellipseBorder>());
        expect(theme.bottomSheetTheme.shape, isA<RoundedSuperellipseBorder>());
        expect(theme.snackBarTheme.shape, isA<RoundedSuperellipseBorder>());
        expect(theme.cardTheme.shape, isA<RoundedSuperellipseBorder>());
        expect(theme.popupMenuTheme.shape, isA<RoundedSuperellipseBorder>());
      });

      test('sheets show a drag handle and snackbars float', () {
        expect(theme.bottomSheetTheme.showDragHandle, isTrue);
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      });

      test('uses Cupertino page transitions on Android', () {
        expect(
          theme.pageTransitionsTheme.builders[TargetPlatform.android],
          isA<CupertinoPageTransitionsBuilder>(),
        );
      });

      test('filled buttons use the accent fill with white text', () {
        final style = theme.filledButtonTheme.style!;
        expect(style.backgroundColor!.resolve({}), AppColors.accentFill);
        expect(style.foregroundColor!.resolve({}), Colors.white);
        expect(style.shape!.resolve({}), isA<RoundedSuperellipseBorder>());
      });

      test('app bar is centered with a hairline bottom border', () {
        expect(theme.appBarTheme.centerTitle, isTrue);
        expect(theme.appBarTheme.shape, isA<Border>());
      });
    });
  }

  test('AppShape falls back to a plain rounded rectangle when disabled', () {
    AppShape.useSuperellipse = false;
    addTearDown(() => AppShape.useSuperellipse = true);
    expect(AppShape.squircle(12), isA<RoundedRectangleBorder>());
    expect(AppShape.squircleTop(12), isA<RoundedRectangleBorder>());
  });

  testWidgets('AppContextColors follows the theme brightness', (tester) async {
    late BuildContext lightContext;
    late BuildContext darkContext;
    await tester.pumpWidget(
      Column(
        textDirection: TextDirection.ltr,
        children: [
          Theme(
            data: AppTheme.light(),
            child: Builder(
              builder: (c) {
                lightContext = c;
                return const SizedBox();
              },
            ),
          ),
          Theme(
            data: AppTheme.dark(),
            child: Builder(
              builder: (c) {
                darkContext = c;
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );

    expect(lightContext.isDark, isFalse);
    expect(lightContext.appSurface, AppColors.surface);
    expect(lightContext.appPrimary, AppColors.primary);
    expect(darkContext.isDark, isTrue);
    expect(darkContext.appSurface, AppColors.surfaceDark);
    expect(darkContext.appPrimary, AppColors.primaryDark);
  });
}
