import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class FeaturedTodoTag {
  final String name;
  final Color color;
  final IconData icon;

  const FeaturedTodoTag({
    required this.name,
    required this.color,
    required this.icon,
  });
}

const featuredTodoTags = [
  FeaturedTodoTag(
    name: 'Sức khỏe',
    color: AppColors.tagGreen,
    icon: Icons.favorite_rounded,
  ),
  FeaturedTodoTag(
    name: 'Tài chính',
    color: AppColors.tagAmber,
    icon: Icons.account_balance_wallet_rounded,
  ),
  FeaturedTodoTag(
    name: 'Sự nghiệp & công việc',
    color: AppColors.tagIndigo,
    icon: Icons.work_rounded,
  ),
  FeaturedTodoTag(
    name: 'Phát triển bản thân',
    color: AppColors.tagPurple,
    icon: Icons.self_improvement_rounded,
  ),
  FeaturedTodoTag(
    name: 'Mối quan hệ (Tình cảm, gia đình, bạn bè)',
    color: AppColors.tagPink,
    icon: Icons.groups_rounded,
  ),
  FeaturedTodoTag(
    name: 'Giải trí',
    color: AppColors.tagCyan,
    icon: Icons.celebration_rounded,
  ),
];

FeaturedTodoTag? featuredTodoTagForName(String name) {
  final normalized = normalizeFeaturedTodoTagName(name);
  for (final tag in featuredTodoTags) {
    if (normalizeFeaturedTodoTagName(tag.name) == normalized) return tag;
  }
  return null;
}

String normalizeFeaturedTodoTagName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
