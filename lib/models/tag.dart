import 'package:flutter/material.dart';
import '../utils/json_utils.dart';

class Tag {
  final String id;
  final String name;
  final Color color;

  const Tag({
    required this.id,
    required this.name,
    required this.color,
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as String,
      name: json['name'] as String,
      color: jsonColor(json['color'] as String? ?? '#888888'),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'color': formatColorHex(color),
      };
}
