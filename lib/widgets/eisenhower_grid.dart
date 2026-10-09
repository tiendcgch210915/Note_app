import 'package:flutter/material.dart';
import '../models/dashboard.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import '../utils/quadrant_utils.dart';
import '../utils/todo_time_utils.dart';
import 'app_surface.dart';
import 'clamp_text_scale.dart';
import 'pressable.dart';
import 'todo_timed_title.dart';

/// 2x2 grid hiển thị count + preview todos cho mỗi quadrant.
/// previews là Map từ 'q1'/'q2'/'q3'/'q4' tới dashboard todos.
class EisenhowerGrid extends StatelessWidget {
  static const int _maxPreviewRows = 5;
  static const double _baseCellHeight = 156;
  static const double _maxTextScale = 1.4;

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
    // Chiều cao ô co giãn theo cỡ chữ hệ thống để nội dung không bị tràn.
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, _maxTextScale);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: _baseCellHeight * scale,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        final q = items[index];
        final info = QuadrantUtils.info(q);
        final key = dashboardQuadrantKeys[index];
        final count = counts[key] ?? 0;
        final preview = previews == null
            ? const <DashboardEisenhowerTodo>[]
            : _sortPreviewTodos(previews![key] ?? const []);
        return ClampTextScale(
          maxScale: _maxTextScale,
          child: _QuadrantCard(
            info: info,
            count: count,
            previewTodos: preview,
            onTap: onTap == null
                ? null
                : () {
                    AppHaptics.light();
                    onTap!(q);
                  },
          ),
        );
      },
    );
  }

  List<DashboardEisenhowerTodo> _sortPreviewTodos(
    List<DashboardEisenhowerTodo> todos,
  ) {
    final sorted = [...todos];
    sorted.sort((a, b) {
      final byTime = compareTodoTimes(a.time, b.time);
      if (byTime != 0) return byTime;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return sorted;
  }
}

class _QuadrantCard extends StatelessWidget {
  /// Số dòng preview tối đa (kể cả dòng "+N việc khác").
  static const int _maxRows = EisenhowerGrid._maxPreviewRows + 1;

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
    final secondary = context.appTextSecondary;

    return Pressable(
      enabled: onTap != null,
      child: AppSurface(
        radius: AppRadius.lg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // Thẻ có nền đặc nên ripple bị che; phản hồi nhấn do Pressable lo.
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(color: info.color),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: info.color,
                        letterSpacing: -0.3,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // EXP 10 — Preview titles. Chiếm đúng phần chiều cao còn lại
                    // của ô nên không bao giờ tràn, dù có bao nhiêu todo.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            _buildPreviews(context, constraints, secondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviews(
    BuildContext context,
    BoxConstraints constraints,
    Color secondary,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    // Ước lượng dư chiều cao 1 dòng (chữ 11sp, dòng cao tới ~1.5 do dấu tiếng
    // Việt + padding trên 2) để không bao giờ xếp quá chỗ trống.
    final rowHeight = scaler.scale(11) * 1.5 + 2;
    final fit = constraints.hasBoundedHeight
        ? (constraints.maxHeight / rowHeight).floor()
        : _maxRows;
    final capacity = fit.clamp(0, _maxRows);

    final total = previewTodos.length;
    int shown;
    if (total <= capacity) {
      shown = total;
    } else if (capacity >= 2) {
      shown = capacity - 1; // chừa 1 dòng cho "+N việc khác"
    } else {
      shown = capacity;
    }
    final hidden = total - shown;

    // SingleChildScrollView + ClipRect là lưới an toàn: nếu ước lượng lệch vài
    // pixel thì phần dư bị cắt gọn thay vì báo "Bottom overflowed".
    return ClipRect(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in previewTodos.take(shown))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: TodoTimedTitle(
                  prefix: '· ',
                  title: t.title,
                  time: t.time,
                  scheduledDate: t.scheduledDate,
                  style: TextStyle(fontSize: 11, color: secondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (hidden > 0 && capacity >= 2)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+$hidden việc khác',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: info.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
