import 'package:flutter/material.dart';
import '../utils/json_utils.dart';

class Tag {
  final String id;
  final String? userId;
  final String name;
  final Color color;
  final int? usageCount;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  const Tag({
    required this.id,
    this.userId,
    required this.name,
    required this.color,
    this.usageCount,
    this.lastUsedAt,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      name: json['name'] as String,
      color: jsonColor(json['color'] as String? ?? '#888888'),
      usageCount: (json['usage_count'] as num?)?.toInt(),
      lastUsedAt: jsonDateNullable(json['last_used_at'] as String?),
      createdAt: jsonDateNullable(json['created_at'] as String?),
      updatedAt: jsonDateNullable(json['updated_at'] as String?),
      deletedAt: jsonDateNullable(json['deleted_at'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (userId != null) 'user_id': userId,
    'name': name,
    'color': formatColorHex(color),
    if (createdAt != null) 'created_at': formatIsoDate(createdAt!),
    if (updatedAt != null) 'updated_at': formatIsoDate(updatedAt!),
    if (deletedAt != null) 'deleted_at': formatIsoDate(deletedAt!),
  };

  String get colorHex => formatColorHex(color);

  bool sameIdentity(Tag other) => id == other.id;
}
