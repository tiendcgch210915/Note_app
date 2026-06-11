import 'package:flutter/material.dart';
import '../utils/json_utils.dart';

enum FrequencyType {
  daily,
  weekly,
  custom;

  String get label {
    switch (this) {
      case FrequencyType.daily:
        return 'Hàng ngày';
      case FrequencyType.weekly:
        return 'Hàng tuần';
      case FrequencyType.custom:
        return 'Tùy chọn';
    }
  }

  String get backendValue => name;

  static FrequencyType parse(String s) {
    switch (s) {
      case 'weekly':
        return FrequencyType.weekly;
      case 'custom':
        return FrequencyType.custom;
      default:
        return FrequencyType.daily;
    }
  }
}

class Habit {
  static const int defaultTargetPerPeriod = 7;

  final String id;
  final String title;
  final String? description;

  /// Server lưu string identifier (vd "book", "fitness"). UI map sang IconData.
  final String? iconName;

  /// Cho UI tiện render — derive từ iconName.
  final IconData? icon;
  final Color color;
  final FrequencyType frequencyType;
  final int targetPerPeriod;
  final List<int>? activeWeekdays; // 1=Mon, 7=Sun
  final DateTime startDate;
  final DateTime? endDate;
  final int currentStreak;
  final int longestStreak;
  final bool isArchived;

  const Habit({
    required this.id,
    required this.title,
    this.description,
    this.iconName,
    this.icon,
    required this.color,
    this.frequencyType = FrequencyType.daily,
    this.targetPerPeriod = defaultTargetPerPeriod,
    this.activeWeekdays,
    required this.startDate,
    this.endDate,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.isArchived = false,
  });

  factory Habit.fromJson(Map<String, dynamic> json) {
    final iconStr = json['icon'] as String?;
    return Habit(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      iconName: iconStr,
      icon: iconFor(iconStr),
      color: jsonColor(json['color'] as String? ?? '#4CAF50'),
      frequencyType: FrequencyType.parse(
        json['frequency_type'] as String? ?? 'daily',
      ),
      targetPerPeriod:
          (json['target_per_period'] as num?)?.toInt() ??
          defaultTargetPerPeriod,
      activeWeekdays: _parseWeekdays(json['active_weekdays'] as String?),
      startDate: jsonDateOnly(json['start_date'] as String),
      endDate: jsonDateOnlyNullable(json['end_date'] as String?),
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longest_streak'] as num?)?.toInt() ?? 0,
      isArchived: jsonBool(json['is_archived']),
    );
  }

  static List<int>? _parseWeekdays(String? s) {
    if (s == null || s.isEmpty) return null;
    return s
        .split(',')
        .map((x) => int.tryParse(x.trim()))
        .whereType<int>()
        .toList();
  }

  /// Body cho POST /habits.
  static Map<String, dynamic> createBody({
    required String title,
    String? description,
    String? icon,
    Color? color,
    FrequencyType frequencyType = FrequencyType.daily,
    int? targetPerPeriod,
    List<int>? activeWeekdays,
    required DateTime startDate,
    DateTime? endDate,
  }) {
    final target =
        targetPerPeriod ??
        createTargetPerPeriod(
          frequencyType: frequencyType,
          startDate: startDate,
          endDate: endDate,
          activeWeekdays: activeWeekdays,
        );
    return {
      'title': title,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': formatColorHex(color),
      'frequency_type': frequencyType.backendValue,
      'target_per_period': target,
      if (activeWeekdays != null) 'active_weekdays': activeWeekdays.join(','),
      'start_date': formatDateOnly(startDate),
      if (endDate != null) 'end_date': formatDateOnly(endDate),
    };
  }

  static int createTargetPerPeriod({
    required FrequencyType frequencyType,
    required DateTime startDate,
    DateTime? endDate,
    List<int>? activeWeekdays,
  }) {
    if (endDate == null) return defaultTargetPerPeriod;

    final start = _dateOnly(startDate);
    final end = _dateOnly(endDate);
    if (end.isBefore(start)) return 1;

    final daysInclusive = end.difference(start).inDays + 1;
    final possible = switch (frequencyType) {
      FrequencyType.daily => daysInclusive,
      FrequencyType.weekly => (daysInclusive + 6) ~/ 7,
      FrequencyType.custom => _countActiveWeekdays(
        start: start,
        daysInclusive: daysInclusive,
        activeWeekdays: activeWeekdays,
      ),
    };
    return possible.clamp(1, defaultTargetPerPeriod).toInt();
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static int _countActiveWeekdays({
    required DateTime start,
    required int daysInclusive,
    List<int>? activeWeekdays,
  }) {
    final weekdays = activeWeekdays?.toSet() ?? const <int>{};
    if (weekdays.isEmpty) return 0;

    var count = 0;
    for (var i = 0; i < daysInclusive; i++) {
      if (weekdays.contains(start.add(Duration(days: i)).weekday)) {
        count++;
      }
    }
    return count;
  }

  String get frequencyLabel {
    switch (frequencyType) {
      case FrequencyType.daily:
        return 'Hàng ngày';
      case FrequencyType.weekly:
        return 'Hàng tuần';
      case FrequencyType.custom:
        return 'Tùy chọn';
    }
  }

  /// Map icon identifier string → IconData.
  static IconData? iconFor(String? identifier) {
    if (identifier == null) return null;
    switch (identifier) {
      case 'book':
        return Icons.menu_book;
      case 'fitness':
        return Icons.fitness_center;
      case 'water':
        return Icons.local_drink;
      case 'meditation':
        return Icons.self_improvement;
      case 'run':
        return Icons.directions_run;
      case 'sleep':
        return Icons.bedtime;
      case 'money':
        return Icons.savings;
      case 'code':
        return Icons.code;
      case 'brush':
        return Icons.brush;
      case 'music':
        return Icons.music_note;
      case 'brain':
        return Icons.psychology;
      case 'eco':
        return Icons.eco;
      case 'lightbulb':
        return Icons.lightbulb_outline;
      case 'heart':
        return Icons.favorite_outline;
      case 'spa':
        return Icons.spa;
      case 'school':
        return Icons.school;
      case 'bolt':
        return Icons.bolt;
      case 'flower':
        return Icons.local_florist;
      case 'sun':
        return Icons.sunny;
      case 'terrain':
        return Icons.terrain;
      default:
        return Icons.flag;
    }
  }
}
