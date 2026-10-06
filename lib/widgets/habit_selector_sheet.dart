import 'package:flutter/material.dart';

import '../data/habits_repository.dart';
import '../models/habit.dart';
import '../theme/app_colors.dart';

class HabitSelection {
  final Habit? habit;

  const HabitSelection(this.habit);
}

Future<HabitSelection?> showHabitSelectorSheet(
  BuildContext context, {
  String? selectedHabitId,
}) {
  return showModalBottomSheet<HabitSelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Liên kết habit',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(const HabitSelection(null)),
                    child: const Text('Không liên kết'),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.link_off_rounded),
              title: const Text('Không liên kết'),
              trailing: selectedId == null
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () =>
                  Navigator.of(context).pop(const HabitSelection(null)),
            ),
            const Divider(height: 1),
            if (_loading && _habits.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (_habits.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Chưa có habit để liên kết'),
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
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: habit.color.withValues(alpha: 0.14),
                        foregroundColor: habit.color,
                        child: Icon(habit.icon ?? Icons.flag, size: 20),
                      ),
                      title: Text(habit.title),
                      subtitle: habit.isArchived
                          ? const Text('Đã lưu trữ')
                          : null,
                      trailing: selected
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
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
