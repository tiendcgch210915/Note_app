import 'package:flutter/material.dart';
import '../models/dashboard.dart';
import '../theme/app_colors.dart';
import '../utils/quadrant_utils.dart';
import 'tag_chip.dart';

/// 2x2 grid hiển thị count + preview todos cho mỗi quadrant.
/// previews là Map từ 'q1'/'q2'/'q3'/'q4' tới dashboard todos.
class EisenhowerGrid extends StatelessWidget {
  final Map<String, int> counts; // q1, q2, q3, q4
  final Map<String, List<DashboardEisenhowerTodo>>? previews;
  final void Function(Quadrant)? onTap;

  const EisenhowerGrid({
    super.key,
    required this.counts,
    this.previews,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = const [Quadrant.q1, Quadrant.q2, Quadrant.q3, Quadrant.q4];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        final q = items[index];
        final info = QuadrantUtils.info(q);
        final key = dashboardQuadrantKeys[index];
        final count = counts[key] ?? 0;
        final preview = previews == null
            ? const <DashboardEisenhowerTodo>[]
            : (previews![key] ?? const []);
        return _QuadrantCard(
          info: info,
          count: count,
          previewTodos: preview,
          onTap: onTap == null ? null : () => onTap!(q),
        );
      },
    );
  }
}

class _QuadrantCard extends StatelessWidget {
  final QuadrantInfo info;
  final int count;
  final List<DashboardEisenhowerTodo> previewTodos;
  final VoidCallback? onTap;

  const _QuadrantCard({
    required this.info,
    required this.count,
    required this.previewTodos,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: info.color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.label,
              style: TextStyle(
                fontSize: 11,
                color: secondary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: info.color,
                    letterSpacing: 0,
                    height: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // EXP 10 — Preview titles
            ...previewTodos
                .take(3)
                .map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '· ${t.title}',
                          style: TextStyle(fontSize: 10, color: secondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (t.tags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, left: 8),
                            child: TodoTagWrap(tags: t.tags.take(2).toList()),
                          ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
