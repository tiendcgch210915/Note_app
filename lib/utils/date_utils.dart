/// Helper ngày tháng tự viết, KHÔNG dùng package intl.
class AppDateUtils {
  AppDateUtils._();

  static const List<String> _weekdaysShort = [
    'T2',
    'T3',
    'T4',
    'T5',
    'T6',
    'T7',
    'CN',
  ];

  static const List<String> _weekdaysLong = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];

  static const List<String> _monthsShort = [
    'Thg 1',
    'Thg 2',
    'Thg 3',
    'Thg 4',
    'Thg 5',
    'Thg 6',
    'Thg 7',
    'Thg 8',
    'Thg 9',
    'Thg 10',
    'Thg 11',
    'Thg 12',
  ];

  /// "T2 18/05" — short header for dashboard.
  static String formatDashboardDate(DateTime date) {
    final wd = _weekdaysShort[date.weekday - 1];
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$wd $dd/$mm';
  }

  /// "Hôm nay, T2 18/05" hoặc "Hôm qua" hoặc "T2 18/05".
  static String formatDashboardTitle(DateTime date, {DateTime? anchor}) {
    final now = anchor ?? DateTime.now();
    if (isSameDay(date, now)) return 'Hôm nay, ${formatDashboardDate(date)}';
    if (isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Hôm qua';
    }
    if (isSameDay(date, now.add(const Duration(days: 1)))) return 'Ngày mai';
    return formatDashboardDate(date);
  }

  /// "18 Thg 5" — dạng ngày dùng cho note card.
  static String formatNoteDate(DateTime date) {
    return '${date.day} ${_monthsShort[date.month - 1]}';
  }

  /// "18/05/2026" — dạng dài.
  static String formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm/${date.year}';
  }

  /// Relative: "Hôm nay", "Hôm qua", "Ngày mai", "2 ngày trước", "Trong 3 ngày".
  static String formatRelative(DateTime date, {DateTime? anchor}) {
    final now = anchor ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

    if (diff == 0) return 'Hôm nay';
    if (diff == -1) return 'Hôm qua';
    if (diff == 1) return 'Ngày mai';
    if (diff < 0) return '${-diff} ngày trước';
    return 'Trong $diff ngày';
  }

  /// "08:30".
  static String formatTime(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static bool isToday(DateTime date, {DateTime? anchor}) {
    final now = anchor ?? DateTime.now();
    return isSameDay(date, now);
  }

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool isPast(DateTime date, {DateTime? anchor}) {
    final now = anchor ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.isBefore(today);
  }

  static bool isFuture(DateTime date, {DateTime? anchor}) {
    final now = anchor ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.isAfter(today);
  }

  static String weekdayShort(int weekday) => _weekdaysShort[weekday - 1];
  static String weekdayLong(int weekday) => _weekdaysLong[weekday - 1];

  /// Trả về ngày chỉ-ngày (00:00) — bỏ giờ phút.
  static DateTime dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
}
