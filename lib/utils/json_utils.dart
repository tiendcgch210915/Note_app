import 'package:flutter/material.dart';

/// Helpers parse JSON theo convention backend:
/// - is_* INTEGER 0/1 ↔ bool
/// - Timestamp ISO 8601 ↔ DateTime
/// - Date-only "YYYY-MM-DD" ↔ DateTime
/// - Color "#aabbcc" ↔ Color
///
/// Tất cả null-safe. Throw FormatException khi parse fail trên giá trị non-null.

/// 0/1 hoặc bool → bool. null hoặc khác → fallback (default false).
bool jsonBool(dynamic v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v == 1;
  if (v is String) {
    if (v == '1' || v.toLowerCase() == 'true') return true;
    if (v == '0' || v.toLowerCase() == 'false') return false;
  }
  return fallback;
}

/// 0/1/null → bool? (dùng cho is_important, is_urgent).
bool? jsonBoolNullable(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v == 1;
  if (v is String) {
    if (v == '1' || v.toLowerCase() == 'true') return true;
    if (v == '0' || v.toLowerCase() == 'false') return false;
  }
  return null;
}

/// ISO 8601 string → DateTime.
DateTime jsonDate(String iso) => DateTime.parse(iso);

DateTime? jsonDateNullable(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.parse(iso);
}

/// "YYYY-MM-DD" → DateTime (date-only, hour=0).
DateTime jsonDateOnly(String yyyymmdd) {
  final parts = yyyymmdd.split('-');
  if (parts.length != 3) {
    throw FormatException('Invalid date-only format: $yyyymmdd');
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

DateTime? jsonDateOnlyNullable(String? s) {
  if (s == null || s.isEmpty) return null;
  return jsonDateOnly(s);
}

/// "#aabbcc" → Color. Hỗ trợ cả "#aabbccdd" (alpha).
Color jsonColor(String hex, {Color fallback = const Color(0xFF888888)}) {
  var clean = hex.replaceAll('#', '').trim();
  if (clean.length == 6) clean = 'FF$clean';
  if (clean.length != 8) return fallback;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return fallback;
  return Color(value);
}

Color? jsonColorNullable(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  return jsonColor(hex);
}

/// DateTime → ISO 8601 UTC string.
String formatIsoDate(DateTime d) => d.toUtc().toIso8601String();

/// DateTime → "YYYY-MM-DD".
String formatDateOnly(DateTime d) {
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

/// Color → "#aabbcc" (bỏ alpha).
String formatColorHex(Color c) {
  final r = (c.r * 255.0).round().toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255.0).round().toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255.0).round().toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}

int boolToInt(bool b) => b ? 1 : 0;
int? boolToIntNullable(bool? b) => b == null ? null : (b ? 1 : 0);
