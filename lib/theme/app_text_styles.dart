import 'package:flutter/material.dart';

/// Các TextStyle dùng chung. Giữ tối giản — chỉ định nghĩa size/weight,
/// để màu chữ kế thừa từ ThemeData để tự đổi theo dark mode.
class AppTextStyles {
  AppTextStyles._();

  // Title cho large header kiểu iOS
  static const largeTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static const title1 = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
  static const title2 = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
  static const title3 = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

  static const body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
  static const bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
  static const bodySmall = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);

  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);

  /// Cho section header style "MA TRẬN EISENHOWER".
  static const sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
  );

  /// Số to (score, streak).
  static const numberHuge = TextStyle(
    fontSize: 56,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
  );

  static const numberLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static const numberMedium = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
  );
}
