import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Loại ô trong Ma Trận Eisenhower.
enum Quadrant {
  q1, // Quan trọng + Khẩn — Làm ngay
  q2, // Quan trọng + Không khẩn — Lên lịch
  q3, // Không quan trọng + Khẩn — Ủy quyền
  q4, // Không quan trọng + Không khẩn — Bỏ qua
  unclassified,
}

class QuadrantInfo {
  final Quadrant quadrant;
  final String label;
  final String action;
  final Color color;

  const QuadrantInfo({
    required this.quadrant,
    required this.label,
    required this.action,
    required this.color,
  });
}

class QuadrantUtils {
  QuadrantUtils._();

  static Quadrant from({bool? important, bool? urgent}) {
    if (important == true && urgent == true) return Quadrant.q1;
    if (important == true && urgent == false) return Quadrant.q2;
    if (important == false && urgent == true) return Quadrant.q3;
    return Quadrant.q4;
  }

  static QuadrantInfo info(Quadrant q) {
    switch (q) {
      case Quadrant.q1:
        return const QuadrantInfo(
          quadrant: Quadrant.q1,
          label: 'Quan trọng & Khẩn',
          action: 'Làm ngay',
          color: AppColors.q1,
        );
      case Quadrant.q2:
        return const QuadrantInfo(
          quadrant: Quadrant.q2,
          label: 'Quan trọng - Không khẩn',
          action: 'Lên lịch',
          color: AppColors.q2,
        );
      case Quadrant.q3:
        return const QuadrantInfo(
          quadrant: Quadrant.q3,
          label: 'Khẩn - Không quan trọng',
          action: 'Ủy quyền',
          color: AppColors.q3,
        );
      case Quadrant.q4:
        return const QuadrantInfo(
          quadrant: Quadrant.q4,
          label: 'Không q.trọng - Không khẩn',
          action: 'Bỏ qua',
          color: AppColors.q4,
        );
      case Quadrant.unclassified:
        return const QuadrantInfo(
          quadrant: Quadrant.unclassified,
          label: 'Chưa phân loại',
          action: 'Phân loại',
          color: AppColors.qUnclassified,
        );
    }
  }
}
