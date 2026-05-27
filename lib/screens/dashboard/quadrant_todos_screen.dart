import 'package:flutter/material.dart';
import '../../models/todo.dart';
import '../../theme/app_colors.dart';
import '../../utils/quadrant_utils.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/todo_tile.dart';
import '../todos/todo_detail_screen.dart';

/// EXP 10 — Hiển thị full list todos của 1 quadrant khi tap ô Dashboard.
class QuadrantTodosScreen extends StatelessWidget {
  final Quadrant quadrant;
  final List<Todo> todos;

  const QuadrantTodosScreen({
    super.key,
    required this.quadrant,
    required this.todos,
  });

  @override
  Widget build(BuildContext context) {
    final info = QuadrantUtils.info(quadrant);
    return Scaffold(
      appBar: AppBar(
        title: Text(info.label),
        backgroundColor: info.color.withValues(alpha: 0.12),
      ),
      body: todos.isEmpty
          ? EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Không có việc nào trong ${info.label}',
              subtitle: 'Action gợi ý: ${info.action}',
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  color: info.color.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 32,
                        decoration: BoxDecoration(
                          color: info.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${todos.length} việc',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'Gợi ý: ${info.action}',
                              style: TextStyle(fontSize: 12, color: info.color, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: todos.length,
                    itemBuilder: (ctx, i) {
                      final t = todos[i];
                      return TodoTile(
                        todo: t,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TodoDetailScreen(todoId: t.id),
                          ),
                        ),
                        onToggleDone: () {}, // Read-only ở screen này
                      );
                    },
                  ),
                ),
              ],
            ),
      backgroundColor: AppColors.background,
    );
  }
}
