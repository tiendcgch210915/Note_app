import 'package:flutter/material.dart';

import '../data/habits_repository.dart';
import '../models/habit.dart';
import '../theme/app_colors.dart';

class HabitLinkChip extends StatelessWidget {
  final String? habitId;
  final String fallbackLabel;

  const HabitLinkChip({
    super.key,
    required this.habitId,
    this.fallbackLabel = 'Habit liên kết',
  });

  @override
  Widget build(BuildContext context) {
    final id = habitId;
    if (id == null || id.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<Habit?>(
      future: HabitsRepository.instance.getLocalHabit(id),
      builder: (context, snapshot) {
        final habit = snapshot.data;
        final color = habit?.color ?? context.appPrimary;
        final label = habit?.title ?? fallbackLabel;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: ShapeDecoration(
            color: color.withValues(alpha: 0.12),
            shape: StadiumBorder(
              side: BorderSide(color: color.withValues(alpha: 0.30)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(habit?.icon ?? Icons.flag_outlined, size: 14, color: color),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
