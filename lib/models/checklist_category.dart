import 'package:flutter/material.dart';

import '../utils/json_utils.dart';

class ChecklistCategory {
  final String id;
  final String userId;
  final String name;
  final String slug;
  final String? icon;
  final Color color;
  final int sortOrder;
  final bool isSystem;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const ChecklistCategory({
    required this.id,
    required this.userId,
    required this.name,
    required this.slug,
    this.icon,
    required this.color,
    this.sortOrder = 0,
    this.isSystem = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory ChecklistCategory.fromJson(Map<String, dynamic> json) {
    return ChecklistCategory(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String,
      slug: json['slug'] as String? ?? '',
      icon: json['icon'] as String?,
      color: jsonColor(json['color'] as String? ?? '#4F46E5'),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isSystem: jsonBool(json['is_system']),
      createdAt: jsonDate(json['created_at'] as String),
      updatedAt: jsonDate(json['updated_at'] as String),
      deletedAt: jsonDateNullable(json['deleted_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'slug': slug,
    'icon': icon,
    'color': formatColorHex(color),
    'sort_order': sortOrder,
    'is_system': isSystem,
    'created_at': formatIsoDate(createdAt),
    'updated_at': formatIsoDate(updatedAt),
    'deleted_at': deletedAt == null ? null : formatIsoDate(deletedAt!),
  };

  static IconData iconFor(String? identifier) {
    switch (identifier) {
      case 'code':
        return Icons.code;
      case 'work':
        return Icons.work_outline;
      case 'health':
        return Icons.favorite_border;
      case 'home':
        return Icons.home_outlined;
      case 'fitness':
        return Icons.fitness_center;
      case 'book':
        return Icons.menu_book;
      case 'money':
        return Icons.savings_outlined;
      case 'travel':
        return Icons.flight_takeoff;
      case 'shopping':
        return Icons.shopping_bag_outlined;
      default:
        return Icons.category_outlined;
    }
  }
}
