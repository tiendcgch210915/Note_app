import 'package:flutter/material.dart';
import '../utils/json_utils.dart';

class Template {
  final String id;
  final String title;
  final String? description;

  /// Server lưu string identifier (vd "sun", "code"). UI map về IconData khi render.
  final String? icon;
  final String? category;
  final String? categoryId;
  final int sortOrder;
  final bool isSystem;
  final int timesUsed;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Template({
    required this.id,
    required this.title,
    this.description,
    this.icon,
    this.category,
    this.categoryId,
    this.sortOrder = 0,
    this.isSystem = false,
    this.timesUsed = 0,
    this.lastUsedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      icon: json['icon'] as String?,
      category: json['category'] as String?,
      categoryId: json['category_id'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isSystem: jsonBool(json['is_system']),
      timesUsed: (json['times_used'] as num?)?.toInt() ?? 0,
      lastUsedAt: jsonDateNullable(json['last_used_at'] as String?),
      createdAt: jsonDate(json['created_at'] as String),
      updatedAt: jsonDate(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'icon': icon,
    'category': category,
    'category_id': categoryId,
    'sort_order': sortOrder,
  };

  Template copyWith({
    String? id,
    String? title,
    String? description,
    String? icon,
    String? category,
    String? categoryId,
    int? sortOrder,
    bool? isSystem,
    int? timesUsed,
    DateTime? lastUsedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Template(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      sortOrder: sortOrder ?? this.sortOrder,
      isSystem: isSystem ?? this.isSystem,
      timesUsed: timesUsed ?? this.timesUsed,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Helper map icon identifier string → IconData. Mở rộng khi cần.
  static IconData iconFor(String? identifier) {
    switch (identifier) {
      case 'sun':
        return Icons.wb_sunny;
      case 'code':
        return Icons.code;
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
      case 'brush':
        return Icons.brush;
      default:
        return Icons.checklist;
    }
  }
}
