import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/habits_repository.dart';
import '../../models/habit.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/habit_card.dart';
import 'habit_detail_screen.dart';

class HabitsListScreen extends StatefulWidget {
  const HabitsListScreen({super.key});

  @override
  State<HabitsListScreen> createState() => _HabitsListScreenState();
}

class _HabitsListScreenState extends State<HabitsListScreen> {
  bool _showArchived = false;
  bool _loading = false;
  List<Habit> _habits = [];
  Map<DateTime, Map<String, bool>> _weekCal = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final today = AppDateUtils.dateOnly(DateTime.now());
      final habitsFut = HabitsRepository.instance.list(includeArchived: _showArchived);
      final calFut = HabitsRepository.instance.getCalendar(
        from: today.subtract(const Duration(days: 7)),
        to: today,
      );
      final results = await Future.wait([habitsFut, calFut]);
      if (!mounted) return;
      setState(() {
        _habits = results[0] as List<Habit>;
        _weekCal = results[1] as Map<DateTime, Map<String, bool>>;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.vnMessage), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _completionsLastWeek(String habitId) {
    var count = 0;
    _weekCal.forEach((date, map) {
      if (map[habitId] == true) count++;
    });
    return count;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _habits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_habits.isEmpty) {
      return EmptyState(
        icon: Icons.local_fire_department_outlined,
        title: _showArchived ? 'Không có habit lưu trữ' : 'Chưa có thói quen nào',
        subtitle: 'Thêm thói quen đầu tiên để bắt đầu xây streak.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              const Text('Hiện archived'),
              Switch(
                value: _showArchived,
                onChanged: (v) {
                  setState(() => _showArchived = v);
                  _refresh();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.80,
              ),
              itemCount: _habits.length,
              itemBuilder: (ctx, i) {
                final h = _habits[i];
                return HabitCard(
                  habit: h,
                  recentCompletions: _completionsLastWeek(h.id),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HabitDetailScreen(habitId: h.id),
                      ),
                    );
                    if (mounted) _refresh();
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
