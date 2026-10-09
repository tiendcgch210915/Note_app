import 'package:flutter/material.dart';

/// Thang bán kính bo góc dùng chung. Thay cho các số rời rạc (4/6/8/10/...).
class AppRadius {
  AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 14;
  static const double lg = 16;
  static const double xl = 20;
  static const double sheet = 28;
  static const double pill = 999;
}

/// Lưới khoảng cách 4pt.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

/// Thời lượng + đường cong animation thống nhất. Chỉ dùng animation hữu hạn.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 350);
  static const Curve curve = Curves.easeOutCubic;
}

/// Hình dạng bo góc. Mặc định dùng "squircle" của iOS
/// ([RoundedSuperellipseBorder]); đặt [useSuperellipse] = false để quay về bo
/// góc thường nếu gặp vấn đề hiển thị/hiệu năng.
class AppShape {
  AppShape._();

  static bool useSuperellipse = true;

  static OutlinedBorder squircle(
    double radius, {
    BorderSide side = BorderSide.none,
  }) => squircleOf(BorderRadius.circular(radius), side: side);

  static OutlinedBorder squircleTop(double radius) =>
      squircleOf(BorderRadius.vertical(top: Radius.circular(radius)));

  static OutlinedBorder squircleOf(
    BorderRadius borderRadius, {
    BorderSide side = BorderSide.none,
  }) {
    return useSuperellipse
        ? RoundedSuperellipseBorder(borderRadius: borderRadius, side: side)
        : RoundedRectangleBorder(borderRadius: borderRadius, side: side);
  }

  static const OutlinedBorder pill = StadiumBorder();
}

/// Bóng đổ rất nhẹ cho thẻ. Dark mode không dùng bóng (dựa vào viền/độ sáng).
class AppShadows {
  AppShadows._();

  static List<BoxShadow> card(bool isDark) {
    if (isDark) return const [];
    return const [
      BoxShadow(color: Color(0x0F101828), blurRadius: 12, offset: Offset(0, 3)),
    ];
  }
}
