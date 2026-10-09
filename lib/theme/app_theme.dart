import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

/// ThemeData light + dark cho toàn app, dùng Material 3 nhưng tinh chỉnh theo
/// phong cách iOS: bo góc squircle, chuyển trang kiểu Cupertino, nút/input/
/// sheet/dialog bo tròn, hiệu ứng nhấn nhẹ thay cho ripple.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // ── Palette theo mode ──
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;
    final primarySoft = isDark
        ? AppColors.primarySoftDark
        : AppColors.primarySoft;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final background = isDark ? AppColors.backgroundDark : AppColors.background;
    final textPrimary = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final divider = isDark ? AppColors.dividerDark : AppColors.divider;
    final toast = isDark ? const Color(0xFF2F3036) : const Color(0xFF1F2937);
    final fieldGray = isDark
        ? const Color(0xFF3F4046)
        : const Color(0xFFD1D5DB);

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
          surface: surface,
          primary: primary,
        ).copyWith(
          onSurface: textPrimary,
          onSurfaceVariant: textSecondary,
          outline: divider,
          outlineVariant: divider,
          surfaceContainerLowest: surface,
          surfaceContainerLow: isDark
              ? const Color(0xFF1B1C20)
              : const Color(0xFFF4F5F8),
          surfaceContainer: isDark
              ? const Color(0xFF1F2024)
              : const Color(0xFFF1F2F6),
          surfaceContainerHigh: isDark
              ? const Color(0xFF26272C)
              : const Color(0xFFECEEF3),
          surfaceContainerHighest: isDark
              ? const Color(0xFF2E2F35)
              : const Color(0xFFE7E9EF),
        );

    // ── Nút ──
    final buttonShape = AppShape.squircle(AppRadius.md);
    final disabledBg = textSecondary.withValues(alpha: 0.16);
    final disabledFg = textSecondary.withValues(alpha: 0.6);
    final buttonText = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      dividerColor: divider,
      splashFactory: NoSplash.splashFactory,
      highlightColor: textPrimary.withValues(alpha: isDark ? 0.08 : 0.05),
      hoverColor: textPrimary.withValues(alpha: 0.04),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        shape: Border(
          bottom: BorderSide(color: divider.withValues(alpha: 0.6), width: 0.5),
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: AppShape.squircle(AppRadius.lg),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentFill,
        foregroundColor: Colors.white,
        elevation: 3,
        highlightElevation: 5,
        shape: CircleBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentFill,
          foregroundColor: Colors.white,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          minimumSize: const Size(0, 50),
          elevation: 0,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentFill,
          foregroundColor: Colors.white,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          minimumSize: const Size(0, 48),
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          disabledForegroundColor: disabledFg,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: divider),
          shape: buttonShape,
          textStyle: buttonText.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          disabledForegroundColor: disabledFg,
          minimumSize: const Size(48, 44),
          shape: AppShape.squircle(AppRadius.sm),
          textStyle: buttonText.copyWith(fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: _inputBorder(divider),
        enabledBorder: _inputBorder(divider),
        disabledBorder: _inputBorder(divider.withValues(alpha: 0.6)),
        focusedBorder: _inputBorder(primary, width: 1.5),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.5),
        hintStyle: TextStyle(color: textSecondary),
        labelStyle: TextStyle(color: textSecondary),
        floatingLabelStyle: TextStyle(
          color: primary,
          fontWeight: FontWeight.w600,
        ),
        errorStyle: const TextStyle(
          color: AppColors.danger,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        helperStyle: TextStyle(color: textSecondary, fontSize: 12),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          color: textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        titleSmall: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: textPrimary, fontSize: 14),
        bodySmall: TextStyle(color: textSecondary, fontSize: 12),
        labelLarge: TextStyle(
          color: textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 0.5, space: 1),
      iconTheme: IconThemeData(color: textPrimary),
      listTileTheme: ListTileThemeData(
        iconColor: textPrimary,
        textColor: textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: AppShape.squircle(AppRadius.xl),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        contentTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 14,
          height: 1.4,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: textSecondary.withValues(alpha: 0.4),
        dragHandleSize: const Size(36, 5),
        clipBehavior: Clip.antiAlias,
        shape: AppShape.squircleTop(AppRadius.sheet),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: toast,
        actionTextColor: const Color(0xFFA5B4FC),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        elevation: 3,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: AppShape.squircle(AppRadius.md),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        shape: AppShape.squircle(AppRadius.md),
        textStyle: TextStyle(
          color: textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accentFill
              : fieldGray,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accentFill
              : Colors.transparent,
        ),
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            width: 1.5,
            color: states.contains(WidgetState.selected)
                ? AppColors.accentFill
                : textSecondary.withValues(alpha: 0.7),
          ),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accentFill
              : textSecondary.withValues(alpha: 0.7),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: StadiumBorder(side: BorderSide(color: divider)),
        side: BorderSide(color: divider),
        backgroundColor: surface,
        selectedColor: AppColors.accentFill,
        disabledColor: surface,
        surfaceTintColor: Colors.transparent,
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : textPrimary,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        indicator: UnderlineTabIndicator(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          borderSide: BorderSide(width: 3, color: primary),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: divider,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        strokeCap: StrokeCap.round,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: AppShape.squircle(24),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: AppShape.squircle(24),
        hourMinuteShape: AppShape.squircle(AppRadius.sm),
        dayPeriodShape: AppShape.squircle(AppRadius.sm),
        dialBackgroundColor: primarySoft,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: toast,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
