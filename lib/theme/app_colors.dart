import 'package:flutter/material.dart';

/// Bảng màu chuẩn cho toàn ứng dụng.
/// Light mode dùng tone trắng/xám nhẹ + accent indigo; dark mode đảo ngược nền,
/// giữ nguyên các màu semantic (quadrant, frog, danger, ...).
class AppColors {
  AppColors._();

  // ─── Light palette ────────────────────────────────────────────────
  static const primary = Color(0xFF4F46E5); // indigo-600
  static const primarySoft = Color(0xFFEEF2FF); // indigo-50
  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFF8F9FB);
  static const noteBackground = Color(0xFFFBF7EE); // Apple Notes be
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const divider = Color(0xFFE5E7EB);

  // ─── Dark palette ─────────────────────────────────────────────────
  static const primaryDark = Color(0xFF818CF8); // indigo-400 — sáng hơn trên nền tối
  static const primarySoftDark = Color(0xFF1E1B4B); // indigo-950
  static const surfaceDark = Color(0xFF1F2024);
  static const backgroundDark = Color(0xFF111114);
  static const noteBackgroundDark = Color(0xFF2A2620); // tone be tối
  static const textPrimaryDark = Color(0xFFF3F4F6);
  static const textSecondaryDark = Color(0xFF9CA3AF);
  static const dividerDark = Color(0xFF2F3036);

  // ─── Eisenhower quadrant ──────────────────────────────────────────
  static const q1 = Color(0xFFEF4444); // đỏ — Quan trọng + Khẩn
  static const q2 = Color(0xFF3B82F6); // xanh dương — Quan trọng + Không khẩn
  static const q3 = Color(0xFFF59E0B); // vàng — Khẩn + Không quan trọng
  static const q4 = Color(0xFF10B981); // xanh lá — Không quan trọng + Không khẩn
  static const qUnclassified = Color(0xFF9CA3AF);

  // ─── Semantic ─────────────────────────────────────────────────────
  static const frog = Color(0xFF16A34A); // emerald cho icon frog
  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const streakGold = Color(0xFFF59E0B);

  // ─── Tag colors preset ────────────────────────────────────────────
  static const tagIndigo = Color(0xFF6366F1);
  static const tagGreen = Color(0xFF22C55E);
  static const tagAmber = Color(0xFFF59E0B);
  static const tagRed = Color(0xFFEF4444);
  static const tagPink = Color(0xFFEC4899);
  static const tagCyan = Color(0xFF06B6D4);
  static const tagPurple = Color(0xFFA855F7);
  static const tagSlate = Color(0xFF64748B);

  /// Trả về màu Eisenhower theo cặp (important, urgent).
  static Color quadrantColor({bool? important, bool? urgent}) {
    if (important == null || urgent == null) return qUnclassified;
    if (important && urgent) return q1;
    if (important && !urgent) return q2;
    if (!important && urgent) return q3;
    return q4;
  }
}
