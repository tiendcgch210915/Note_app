import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Bảng icon + màu dùng khi tạo/sửa thói quen (dùng chung cho cả 2 màn hình).
class HabitStylePool {
  HabitStylePool._();

  /// (định danh lưu ở backend, IconData để hiển thị)
  static const icons = <(String, IconData)>[
    ('book', Icons.menu_book),
    ('fitness', Icons.fitness_center),
    ('water', Icons.local_drink),
    ('meditation', Icons.self_improvement),
    ('run', Icons.directions_run),
    ('sleep', Icons.bedtime),
    ('money', Icons.savings),
    ('code', Icons.code),
    ('brush', Icons.brush),
    ('music', Icons.music_note),
    ('brain', Icons.psychology),
    ('eco', Icons.eco),
    ('lightbulb', Icons.lightbulb_outline),
    ('heart', Icons.favorite_outline),
    ('spa', Icons.spa),
    ('school', Icons.school),
    ('bolt', Icons.bolt),
    ('flower', Icons.local_florist),
    ('sun', Icons.sunny),
    ('terrain', Icons.terrain),
  ];

  static const colors = <Color>[
    AppColors.primary,
    AppColors.tagGreen,
    AppColors.tagAmber,
    AppColors.tagRed,
    AppColors.tagPink,
    AppColors.tagCyan,
    AppColors.tagPurple,
    AppColors.tagSlate,
  ];

  /// Màu mặc định khi tạo mới — luôn nằm trong [colors] nên sheet chọn màu có
  /// một ô được đánh dấu sẵn.
  static const defaultColor = AppColors.primary;
}
