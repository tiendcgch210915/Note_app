import 'package:flutter/material.dart';

import '../data/habits_repository.dart';
import '../models/habit.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'app_sheet.dart';
import 'app_state_views.dart';

class HabitSelection {
  final Habit? habit;

  const HabitSelection(this.habit);
}

Future<HabitSelection?> showHabitSelectorSheet(
  BuildContext context, {
  String? selectedHabitId,
}) {
  return showAppSheet<HabitSelection>(
    context: context,
    builder: (_) => _HabitSelectorSheet(selectedHabitId: selectedHabitId),
  );
}

class _HabitSelectorSheet extends StatefulWidget {
  final String? selectedHabitId;

  const _HabitSelectorSheet({this.selectedHabitId});

  @override
  State<_HabitSelectorSheet> createState() => _HabitSelectorSheetState();
}

class _HabitSelectorSheetState extends State<_HabitSelectorSheet> {
  List<Habit> _habits = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final local = await HabitsRepository.instance.listLocal(
        includeArchived: true,
      );
      if (mounted) {
        setState(() {
          _habits = _sort(local);
          _loading = false;
        });
      }
      final remote = await HabitsRepository.instance.list(
        includeArchived: true,
      );
      if (mounted) setState(() => _habits = _sort(remote));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Habit> _sort(List<Habit> source) {
    final byId = <String, Habit>{for (final habit in source) habit.id: habit};
    final items = byId.values.toList();
    items.sort((a, b) {
      final archivedOrder = (a.isArchived ? 1 : 0).compareTo(
        b.isArchived ? 1 : 0,
      );
      if (archivedOrder != 0) return archivedOrder;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.selectedHabitId;
    final accent = context.appPrimary;
    final check = Icon(Icons.check_circle_rounded, color: accent);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSheetHeader(title: 'Liên kết habit'),
            ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: ShapeDecoration(
                  color: context.appTextSecondary.withValues(alpha: 0.14),
                  shape: AppShape.squircle(AppRadius.sm),
                ),
                child: Icon(
                  Icons.link_off_rounded,
                  size: 20,
                  color: context.appTextSecondary,
                ),
              ),
              title: const Text('Không liên kết'),
              trailing: selectedId == null ? check : null,
              onTap: () =>
                  Navigator.of(context).pop(const HabitSelection(null)),
            ),
            Divider(height: 0.5, indent: 70, color: context.appDivider),
            if (_loading && _habits.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: AppSpinner())
            else if (_habits.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Chưa có habit để liên kết',
                  style: TextStyle(color: context.appTextSecondary),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _habits.length,
                  itemBuilder: (context, index) {
                    final habit = _habits[index];
                    final selected = habit.id == selectedId;
                    return ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: ShapeDecoration(
                          color: habit.color.withValues(alpha: 0.14),
                          shape: AppShape.squircle(AppRadius.sm),
                        ),
                        child: Icon(
                          habit.icon ?? Icons.flag,
                          size: 20,
                          color: habit.color,
                        ),
                      ),
                      title: Text(habit.title),
                      subtitle: habit.isArchived
                          ? const Text('Đã lưu trữ')
                          : null,
                      trailing: selected ? check : null,
                      onTap: () =>
                          Navigator.of(context).pop(HabitSelection(habit)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
