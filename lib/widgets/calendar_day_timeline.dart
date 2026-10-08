import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import '../theme/app_colors.dart';
import '../utils/date_utils.dart';
import '../utils/todo_time_utils.dart';
import 'todo_swipe_actions.dart';
import 'todo_timed_title.dart';

class CalendarDayTimeline extends StatelessWidget {
  final CalendarDayDetail detail;
  final DateTime? now;
  final ValueChanged<CalendarDayTodo>? onTodoTap;
  final ValueChanged<CalendarDayTodo>? onTodoComplete;
  final ValueChanged<CalendarDayTodo>? onTodoPickTime;
  final ValueChanged<CalendarDayTodo>? onTodoEdit;
  final double minuteHeight;
  final bool centerCurrentTimeOnShow;

  const CalendarDayTimeline({
    super.key,
    required this.detail,
    this.now,
    this.onTodoTap,
    this.onTodoComplete,
    this.onTodoPickTime,
    this.onTodoEdit,
    this.minuteHeight = 1.15,
    this.centerCurrentTimeOnShow = false,
  });

  static const double _leftGutter = 64;
  static const double _rightMargin = 16;
  static const double _topPadding = 18;
  static const double _bottomPadding = 40;
  static const double _emptyHourHeight = 52;
  static const double _emptyHalfHourHeight = 26;
  static const double _occupiedHourMinHeight = 136;
  static const double _occupiedHalfHourMinHeight = 68;
  static const double _currentTimeHalfHourMinHeight = 136;
  static const double _durationContinuationHalfHourHeight = 68;
  static const double _todoCardHeight = 60;
  static const double _doneTodoCardHeight = 34;
  static const double _todoCardGap = 6;
  static const double _slotBottomPadding = 8;
  static const double _maxMinuteOffset = 220;
  static const double _compactMinuteOffset = 8;
  static const double _currentTimeMarkClearance = 16;

  @override
  Widget build(BuildContext context) {
    final timed = detail.timedTodos;
    final untimed = detail.untimedTodos;
    if (timed.isEmpty && untimed.isEmpty) {
      return const _CalendarEmptyState();
    }

    return _CenterOnCurrentTime(
      enabled: centerCurrentTimeOnShow,
      builder: (context, currentTimeKey) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (untimed.isNotEmpty)
            _UntimedTodosSection(
              todos: untimed,
              onTodoTap: onTodoTap,
              onTodoComplete: onTodoComplete,
              onTodoPickTime: onTodoPickTime,
              onTodoEdit: onTodoEdit,
            ),
          if (timed.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                untimed.isEmpty ? 4 : 18,
                16,
                10,
              ),
              child: Text(
                'Timeline 24h',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) =>
                  _buildTimeline(context, constraints.maxWidth, currentTimeKey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeline(
    BuildContext context,
    double width,
    GlobalKey currentTimeKey,
  ) {
    final timeline = detail.timeline;
    final start = timeline.startMinute;
    final end = timeline.endMinute <= start ? 1440 : timeline.endMinute;
    final items = _timedTodoLayouts(context, start, end, width);
    final indicator = _EffectiveIndicator.from(
      detail: detail,
      now: now ?? DateTime.now(),
      startMinute: start,
      endMinute: end,
      halfHourMarks: _TimelineGeometry.visibleHalfHourMarks(start, end, items),
    );
    final geometry = _TimelineGeometry.build(
      startMinute: start,
      endMinute: end,
      items: items,
      currentMinute: indicator.visible
          ? indicator.lineMinutesSinceMidnight
          : null,
    );
    final height = _topPadding + geometry.height + _bottomPadding;

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ...timeline.hourMarks.map(
            (mark) => _buildHourMark(context, mark, indicator, geometry),
          ),
          ...geometry.halfHourMarks.map(
            (minute) =>
                _buildHalfHourMark(context, minute, indicator, geometry),
          ),
          ...items.map((item) {
            final top = _topPadding + geometry.itemTop(item);
            final timedHeight = item.hasDuration
                ? geometry.minuteTop(item.endMinute) - geometry.itemTop(item)
                : item.cardHeight;
            final height = timedHeight < item.cardHeight
                ? item.cardHeight
                : timedHeight;
            return Positioned(
              top: top,
              left: _leftGutter,
              right: _rightMargin,
              height: height,
              child: TodoSwipeActions(
                direction: TodoSwipeDirection.right,
                actionAlignment: TodoSwipeActionAlignment.top,
                enabled:
                    item.todo.id.isNotEmpty &&
                    !item.todo.isDailyLog &&
                    (onTodoPickTime != null || onTodoEdit != null),
                onPickTime: onTodoPickTime == null
                    ? () {}
                    : () => onTodoPickTime!(item.todo),
                onEdit: onTodoEdit == null
                    ? null
                    : () => onTodoEdit!(item.todo),
                child: _CalendarTodoCard(
                  key: ValueKey('calendar-todo-${item.todo.id}'),
                  todo: item.todo,
                  now: now,
                  onTap: onTodoTap == null ? null : () => onTodoTap!(item.todo),
                  onCompleteTap:
                      onTodoComplete == null ||
                          item.todo.isDone ||
                          item.todo.isDailyLog
                      ? null
                      : () => onTodoComplete!(item.todo),
                ),
              ),
            );
          }),
          if (indicator.visible)
            _buildCurrentTimeLine(context, indicator, geometry, currentTimeKey),
        ],
      ),
    );
  }

  Widget _buildHourMark(
    BuildContext context,
    CalendarHourMark mark,
    _EffectiveIndicator indicator,
    _TimelineGeometry geometry,
  ) {
    final isHidden =
        indicator.visible && mark.minute == indicator.hiddenHourMarkMinute;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark ? AppColors.dividerDark : AppColors.divider;
    final labelColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final top = _topPadding + geometry.minuteTop(mark.minute);

    return Positioned(
      key: ValueKey('calendar-hour-mark-${mark.minute}'),
      top: top,
      left: 16,
      right: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            child: isHidden
                ? const SizedBox.shrink()
                : Text(
                    mark.label,
                    key: ValueKey('calendar-hour-label-${mark.minute}'),
                    style: TextStyle(
                      fontSize: 11,
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
          ),
          const SizedBox(width: 4),
          Expanded(child: Container(height: 1, color: lineColor)),
        ],
      ),
    );
  }

  Widget _buildHalfHourMark(
    BuildContext context,
    int minute,
    _EffectiveIndicator indicator,
    _TimelineGeometry geometry,
  ) {
    final isHidden =
        indicator.visible && minute == indicator.hiddenHourMarkMinute;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = (isDark ? AppColors.dividerDark : AppColors.divider)
        .withValues(alpha: 0.72);
    final labelColor =
        (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)
            .withValues(alpha: 0.78);
    final top = _topPadding + geometry.minuteTop(minute);

    return Positioned(
      key: ValueKey('calendar-half-hour-mark-$minute'),
      top: top,
      left: 16,
      right: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            child: isHidden
                ? const SizedBox.shrink()
                : Text(
                    _formatMinuteLabel(minute),
                    key: ValueKey('calendar-half-hour-label-$minute'),
                    style: TextStyle(
                      fontSize: 10,
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
          ),
          const SizedBox(width: 4),
          Expanded(child: Container(height: 1, color: lineColor)),
        ],
      ),
    );
  }

  Widget _buildCurrentTimeLine(
    BuildContext context,
    _EffectiveIndicator indicator,
    _TimelineGeometry geometry,
    GlobalKey currentTimeKey,
  ) {
    final top =
        _topPadding +
        geometry.currentTimeTop(
          indicator.lineMinutesSinceMidnight,
          hiddenMarkMinute: indicator.hiddenHourMarkMinute,
        );
    return Positioned(
      key: const ValueKey('calendar-current-time-line'),
      top: top,
      left: 16,
      right: 16,
      child: Row(
        key: currentTimeKey,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              indicator.label,
              key: const ValueKey('calendar-current-time-label'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.danger,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMinuteLabel(int minute) {
    final normalized = minute >= 1440 ? 0 : minute.clamp(0, 1439).toInt();
    final hour = normalized ~/ 60;
    final min = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  List<_TimedTodoLayout> _timedTodoLayouts(
    BuildContext context,
    int start,
    int end,
    double width,
  ) {
    final cardWidth = width - _leftGutter - _rightMargin;
    final items = <_TimedTodoLayout>[];
    for (final todo in detail.timedTodos) {
      final minute = todo.minutesSinceMidnight ?? todoTimeMinutes(todo.time);
      if (minute == null) continue;
      final clampedStart = minute.clamp(start, end).toInt();
      final estimated = todo.estimatedMinutes;
      final hasDuration = !todo.isDone && estimated != null && estimated > 0;
      final endMinute = hasDuration
          ? (clampedStart + estimated).clamp(start, end).toInt()
          : clampedStart;
      items.add(
        _TimedTodoLayout(
          todo: todo,
          startMinute: clampedStart,
          endMinute: endMinute <= clampedStart ? clampedStart : endMinute,
          hasDuration: hasDuration,
          cardHeight: todo.isDone
              ? _doneTodoCardHeight
              : _CalendarTodoCard.measureHeight(
                  context,
                  todo: todo,
                  cardWidth: cardWidth,
                ),
        ),
      );
    }
    items.sort((a, b) {
      final byStart = a.startMinute.compareTo(b.startMinute);
      if (byStart != 0) return byStart;
      final byPosition = a.todo.position.compareTo(b.todo.position);
      if (byPosition != 0) return byPosition;
      return a.todo.id.compareTo(b.todo.id);
    });
    return items;
  }
}

/// Khi [enabled], đưa vạch giờ hiện tại vào giữa vùng cuộn đúng một lần ngay
/// sau khi timeline xuất hiện. Vạch này chỉ có ở ngày hôm nay nên các ngày
/// khác không bị cuộn.
class _CenterOnCurrentTime extends StatefulWidget {
  final bool enabled;
  final Widget Function(BuildContext context, GlobalKey currentTimeKey) builder;

  const _CenterOnCurrentTime({required this.enabled, required this.builder});

  @override
  State<_CenterOnCurrentTime> createState() => _CenterOnCurrentTimeState();
}

class _CenterOnCurrentTimeState extends State<_CenterOnCurrentTime> {
  final GlobalKey _currentTimeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _center());
    }
  }

  void _center() {
    if (!mounted) return;
    final target = _currentTimeKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(target, alignment: 0.5);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _currentTimeKey);
}

class _TimedTodoLayout {
  final CalendarDayTodo todo;
  final int startMinute;
  final int endMinute;
  final bool hasDuration;
  final double cardHeight;

  const _TimedTodoLayout({
    required this.todo,
    required this.startMinute,
    required this.endMinute,
    required this.hasDuration,
    required this.cardHeight,
  });
}

class _TimelineGeometry {
  final int startMinute;
  final int endMinute;
  final List<_TimelineSlot> slots;
  final Map<String, double> itemOffsets;
  final double height;

  const _TimelineGeometry({
    required this.startMinute,
    required this.endMinute,
    required this.slots,
    required this.itemOffsets,
    required this.height,
  });

  List<int> get halfHourMarks => _halfHourMarksOf(slots);

  /// Vạch xx:30 chỉ hiện khi cả hai nửa giờ đều có todo bắt đầu trong đó.
  static List<int> visibleHalfHourMarks(
    int startMinute,
    int endMinute,
    List<_TimedTodoLayout> items,
  ) {
    return _halfHourMarksOf(_buildSlots(startMinute, endMinute, items));
  }

  static List<int> _halfHourMarksOf(List<_TimelineSlot> slots) {
    return [
      for (final slot in slots)
        if (slot.showsHalfHourMark) slot.startMinute,
    ];
  }

  static _TimelineGeometry build({
    required int startMinute,
    required int endMinute,
    required List<_TimedTodoLayout> items,
    int? currentMinute,
  }) {
    final slots = _buildSlots(startMinute, endMinute, items);

    final offsets = <String, double>{};
    var cumulativeTop = 0.0;
    for (final slot in slots) {
      final startingItems = items
          .where((item) => slot.containsStart(item.startMinute, endMinute))
          .toList(growable: false);
      final touchesAnyTodo = items.any(
        (item) => item.hasDuration
            ? slot.intersectsDuration(item)
            : slot.containsStart(item.startMinute, endMinute),
      );
      var slotHeight = _initialSlotHeight(
        slot,
        touchesAnyTodo,
        startingItems,
        currentMinute,
        endMinute,
      );

      if (startingItems.isNotEmpty) {
        var localOffsets = <String, double>{};
        for (var pass = 0; pass < 8; pass++) {
          final layout = _layoutStartingItems(startingItems, slot, slotHeight);
          localOffsets = layout.offsets;
          final nextHeight = layout.neededHeight;
          if ((nextHeight - slotHeight).abs() < 0.5) {
            slotHeight = nextHeight;
            break;
          }
          slotHeight = nextHeight;
        }
        for (final entry in localOffsets.entries) {
          offsets[entry.key] = cumulativeTop + entry.value;
        }
      }

      slot.top = cumulativeTop;
      slot.height = slotHeight;
      cumulativeTop += slotHeight;
    }

    return _TimelineGeometry(
      startMinute: startMinute,
      endMinute: endMinute,
      slots: slots,
      itemOffsets: offsets,
      height: cumulativeTop,
    );
  }

  static List<_TimelineSlot> _buildSlots(
    int startMinute,
    int endMinute,
    List<_TimedTodoLayout> items,
  ) {
    final slots = <_TimelineSlot>[];
    for (var minute = startMinute; minute < endMinute; minute += 60) {
      final hourEnd = (minute + 60).clamp(startMinute, endMinute).toInt();
      final halfEnd = (minute + 30).clamp(startMinute, hourEnd).toInt();
      final canSplit = halfEnd > minute && halfEnd < hourEnd;
      if (!canSplit) {
        slots.add(_TimelineSlot(startMinute: minute, endMinute: hourEnd));
        continue;
      }

      final firstHalf = _TimelineSlot(startMinute: minute, endMinute: halfEnd);
      final secondHalf = _TimelineSlot(
        startMinute: halfEnd,
        endMinute: hourEnd,
      );
      final firstHasStart = _slotContainsStartingTodo(
        firstHalf,
        items,
        endMinute,
      );
      final secondHasStart = _slotContainsStartingTodo(
        secondHalf,
        items,
        endMinute,
      );
      final hourHasStart = firstHasStart || secondHasStart;

      if (!hourHasStart) {
        slots.add(_TimelineSlot(startMinute: minute, endMinute: hourEnd));
      } else {
        firstHalf.hasStartInHour = true;
        secondHalf.hasStartInHour = true;
        secondHalf.showsHalfHourMark = firstHasStart && secondHasStart;
        slots.add(firstHalf);
        slots.add(secondHalf);
      }
    }
    if (slots.isEmpty) {
      slots.add(_TimelineSlot(startMinute: startMinute, endMinute: endMinute));
    }
    return slots;
  }

  static bool _slotContainsStartingTodo(
    _TimelineSlot slot,
    List<_TimedTodoLayout> items,
    int timelineEndMinute,
  ) {
    return items.any(
      (item) => slot.containsStart(item.startMinute, timelineEndMinute),
    );
  }

  static double _initialSlotHeight(
    _TimelineSlot slot,
    bool touchesAnyTodo,
    List<_TimedTodoLayout> startingItems,
    int? currentMinute,
    int timelineEndMinute,
  ) {
    final isHalfHour = slot.endMinute - slot.startMinute <= 30;
    final containsCurrentTime =
        currentMinute != null &&
        slot.containsMinute(currentMinute, timelineEndMinute);
    final compactHeight = isHalfHour
        ? CalendarDayTimeline._emptyHalfHourHeight
        : CalendarDayTimeline._emptyHourHeight;
    if (!touchesAnyTodo) {
      return containsCurrentTime && isHalfHour
          ? CalendarDayTimeline._currentTimeHalfHourMinHeight
          : compactHeight;
    }
    if (startingItems.isNotEmpty &&
        startingItems.every((item) => item.todo.isDone)) {
      return containsCurrentTime && isHalfHour
          ? CalendarDayTimeline._currentTimeHalfHourMinHeight
          : compactHeight;
    }
    if (startingItems.isEmpty && isHalfHour && slot.hasStartInHour) {
      return containsCurrentTime
          ? CalendarDayTimeline._currentTimeHalfHourMinHeight
          : CalendarDayTimeline._durationContinuationHalfHourHeight;
    }
    if (startingItems.isEmpty) {
      return containsCurrentTime && isHalfHour
          ? CalendarDayTimeline._currentTimeHalfHourMinHeight
          : compactHeight;
    }
    if (isHalfHour) {
      final hasOffsetStart = startingItems.any(
        (item) => item.startMinute > slot.startMinute,
      );
      final stackHeight =
          _stackHeightForItems(startingItems) +
          (hasOffsetStart ? CalendarDayTimeline._compactMinuteOffset : 0);
      final minHeight = containsCurrentTime
          ? CalendarDayTimeline._currentTimeHalfHourMinHeight
          : CalendarDayTimeline._occupiedHalfHourMinHeight;
      return stackHeight < minHeight ? minHeight : stackHeight;
    }
    return CalendarDayTimeline._occupiedHourMinHeight;
  }

  static double _stackHeightForItems(List<_TimedTodoLayout> items) {
    if (items.isEmpty) return 0;
    final cardsHeight = items.fold<double>(
      0,
      (sum, item) => sum + item.cardHeight,
    );
    return cardsHeight +
        CalendarDayTimeline._todoCardGap * (items.length - 1) +
        CalendarDayTimeline._slotBottomPadding;
  }

  double itemTop(_TimedTodoLayout item) {
    return itemOffsets[item.todo.id] ?? minuteTop(item.startMinute);
  }

  double currentTimeTop(int minute, {required int hiddenMarkMinute}) {
    var top = minuteTop(minute);
    if (hiddenMarkMinute >= startMinute && hiddenMarkMinute <= endMinute) {
      final markTop = minuteTop(hiddenMarkMinute);
      const clearance = CalendarDayTimeline._currentTimeMarkClearance;
      if (hiddenMarkMinute > minute) {
        final maxTop = (markTop - clearance).clamp(0.0, height).toDouble();
        if (top > maxTop) top = maxTop;
      } else if (hiddenMarkMinute < minute) {
        final minTop = (markTop + clearance).clamp(0.0, height).toDouble();
        if (top < minTop) top = minTop;
      }
    }
    return top.clamp(0.0, height).toDouble();
  }

  double minuteTop(int minute) {
    final clamped = minute.clamp(startMinute, endMinute).toInt();
    if (clamped <= startMinute) return 0;
    if (clamped >= endMinute) return height;
    for (final slot in slots) {
      if (clamped >= slot.startMinute && clamped <= slot.endMinute) {
        final length = (slot.endMinute - slot.startMinute).clamp(1, 1440);
        final ratio = ((clamped - slot.startMinute) / length).toDouble();
        return slot.top + slot.height * ratio;
      }
    }
    return height;
  }

  static _SlotItemLayout _layoutStartingItems(
    List<_TimedTodoLayout> items,
    _TimelineSlot slot,
    double slotHeight,
  ) {
    final offsets = <String, double>{};
    var cursor = 0.0;
    var neededHeight = slotHeight;
    for (final item in items) {
      final offset = _naturalStartOffsetForHeight(
        item.startMinute,
        slot,
        slotHeight,
        item.cardHeight,
      );
      final placed = offset > cursor ? offset : cursor;
      offsets[item.todo.id] = placed;
      cursor = placed + item.cardHeight + CalendarDayTimeline._todoCardGap;
      final needed =
          placed + item.cardHeight + CalendarDayTimeline._slotBottomPadding;
      if (needed > neededHeight) neededHeight = needed;
    }
    return _SlotItemLayout(offsets: offsets, neededHeight: neededHeight);
  }

  static double _naturalStartOffsetForHeight(
    int minute,
    _TimelineSlot slot,
    double slotHeight,
    double cardHeight,
  ) {
    final length = (slot.endMinute - slot.startMinute).clamp(1, 1440);
    final ratio = ((minute - slot.startMinute) / length)
        .clamp(0.0, 1.0)
        .toDouble();
    if (ratio <= 0) return 0;
    final proportional = ratio * slotHeight;
    final slotIsHalfHour = slot.endMinute - slot.startMinute <= 30;
    final compactOffset =
        slotIsHalfHour &&
            proportional > CalendarDayTimeline._compactMinuteOffset
        ? CalendarDayTimeline._compactMinuteOffset
        : proportional;
    final contained =
        slotHeight - cardHeight - CalendarDayTimeline._slotBottomPadding;
    final maxOffset = contained
        .clamp(0.0, CalendarDayTimeline._maxMinuteOffset)
        .toDouble();
    return compactOffset.clamp(0.0, maxOffset).toDouble();
  }
}

class _SlotItemLayout {
  final Map<String, double> offsets;
  final double neededHeight;

  const _SlotItemLayout({required this.offsets, required this.neededHeight});
}

class _TimelineSlot {
  final int startMinute;
  final int endMinute;
  bool hasStartInHour = false;
  bool showsHalfHourMark = false;
  double top = 0;
  double height = CalendarDayTimeline._emptyHourHeight;

  _TimelineSlot({required this.startMinute, required this.endMinute});

  bool containsStart(int minute, int timelineEndMinute) {
    return containsMinute(minute, timelineEndMinute);
  }

  bool containsMinute(int minute, int timelineEndMinute) {
    if (minute == timelineEndMinute) {
      return endMinute == timelineEndMinute;
    }
    return minute >= startMinute && minute < endMinute;
  }

  bool intersectsDuration(_TimedTodoLayout item) {
    return item.startMinute < endMinute && item.endMinute > startMinute;
  }
}

class _UntimedTodosSection extends StatelessWidget {
  final List<CalendarDayTodo> todos;
  final ValueChanged<CalendarDayTodo>? onTodoTap;
  final ValueChanged<CalendarDayTodo>? onTodoComplete;
  final ValueChanged<CalendarDayTodo>? onTodoPickTime;
  final ValueChanged<CalendarDayTodo>? onTodoEdit;

  const _UntimedTodosSection({
    required this.todos,
    this.onTodoTap,
    this.onTodoComplete,
    this.onTodoPickTime,
    this.onTodoEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Không có giờ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...todos.map(
            (todo) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TodoSwipeActions(
                direction: TodoSwipeDirection.right,
                actionAlignment: TodoSwipeActionAlignment.top,
                enabled:
                    todo.id.isNotEmpty &&
                    !todo.isDailyLog &&
                    (onTodoPickTime != null || onTodoEdit != null),
                onPickTime: onTodoPickTime == null
                    ? () {}
                    : () => onTodoPickTime!(todo),
                onEdit: onTodoEdit == null ? null : () => onTodoEdit!(todo),
                child: _CalendarTodoCard(
                  key: ValueKey('calendar-untimed-todo-${todo.id}'),
                  todo: todo,
                  onTap: onTodoTap == null ? null : () => onTodoTap!(todo),
                  onCompleteTap:
                      onTodoComplete == null || todo.isDone || todo.isDailyLog
                      ? null
                      : () => onTodoComplete!(todo),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarTodoCard extends StatelessWidget {
  final CalendarDayTodo todo;
  final DateTime? now;
  final VoidCallback? onTap;
  final VoidCallback? onCompleteTap;

  const _CalendarTodoCard({
    super.key,
    required this.todo,
    this.now,
    this.onTap,
    this.onCompleteTap,
  });

  static const double _borderWidth = 1;
  static const double _horizontalPadding = 10;
  static const double _verticalPadding = 8;
  static const double _leadingSize = 34;
  static const double _leadingGap = 4;
  static const double _metaTopGap = 4;
  static const double _metaSpacing = 6;
  static const double _metaRunSpacing = 4;
  static const TextStyle _titleStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static List<_MetaSpec> _metaSpecs(CalendarDayTodo todo, Color secondary) {
    return [
      if (todo.isDailyLog)
        _MetaSpec(
          Icons.lock_rounded,
          todo.lockedCompleted == true ? 'Đã chốt' : 'Đã chốt: chưa xong',
          secondary,
        ),
      if (todo.estimatedMinutes != null)
        _MetaSpec(
          Icons.hourglass_empty,
          '${todo.estimatedMinutes} phút',
          secondary,
        ),
      if (todo.hasSubtasks)
        _MetaSpec(Icons.account_tree_outlined, 'Có việc con', secondary),
      for (final tag in todo.tags.take(2))
        _MetaSpec(Icons.local_offer_outlined, tag.name, tag.color),
    ];
  }

  /// Chiều cao cần thiết của thẻ đang mở trong timeline (tiêu đề tối đa 2
  /// dòng + hàng meta có thể xuống dòng), không nhỏ hơn chiều cao tối thiểu.
  static double measureHeight(
    BuildContext context, {
    required CalendarDayTodo todo,
    required double cardWidth,
  }) {
    final textWidth =
        cardWidth -
        2 * _borderWidth -
        2 * _horizontalPadding -
        _leadingSize -
        _leadingGap;
    if (textWidth <= 0) return CalendarDayTimeline._todoCardHeight;

    // Thẻ nằm dưới Material nên text mặc định là bodyMedium.
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    final titleHeight = TodoTimedTitle.measureHeight(
      context,
      title: todo.title,
      time: todo.time,
      maxWidth: textWidth,
      style: _titleStyle,
      baseStyle: bodyStyle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final metas = _metaSpecs(todo, Colors.transparent);
    final metaHeight = metas.isEmpty
        ? 0.0
        : _metaTopGap +
              _measureMetaHeight(context, metas, textWidth, bodyStyle);
    final content = math.max(_leadingSize, titleHeight + metaHeight);
    final height = (2 * _borderWidth + 2 * _verticalPadding + content)
        .ceilToDouble();
    return math.max(height, CalendarDayTimeline._todoCardHeight);
  }

  static double _measureMetaHeight(
    BuildContext context,
    List<_MetaSpec> metas,
    double maxWidth,
    TextStyle? bodyStyle,
  ) {
    final style = (bodyStyle ?? DefaultTextStyle.of(context).style).merge(
      _MiniMeta.textStyle(Colors.transparent),
    );
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final scaler = MediaQuery.textScalerOf(context);

    var total = 0.0;
    var lineWidth = 0.0;
    var lineHeight = 0.0;
    for (final meta in metas) {
      final painter = TextPainter(
        text: TextSpan(text: meta.label, style: style),
        textDirection: direction,
        locale: locale,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final chipWidth = _MiniMeta.iconSize + _MiniMeta.iconGap + painter.width;
      final chipHeight = math.max(_MiniMeta.iconSize, painter.height);
      painter.dispose();

      if (lineWidth > 0 && lineWidth + _metaSpacing + chipWidth > maxWidth) {
        total += lineHeight + _metaRunSpacing;
        lineWidth = chipWidth;
        lineHeight = chipHeight;
      } else {
        lineWidth += (lineWidth > 0 ? _metaSpacing : 0) + chipWidth;
        lineHeight = math.max(lineHeight, chipHeight);
      }
    }
    return total + lineHeight;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final border = isDark ? AppColors.dividerDark : AppColors.divider;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    if (todo.isDone) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            height: CalendarDayTimeline._doneTodoCardHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: secondary.withValues(alpha: isDark ? 0.08 : 0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: secondary.withValues(alpha: 0.16)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TodoTimedTitle(
                    title: todo.title,
                    time: todo.time,
                    scheduledDate: todo.scheduledDate,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: secondary.withValues(alpha: 0.68),
                      decoration: TextDecoration.lineThrough,
                      decorationColor: secondary.withValues(alpha: 0.46),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    now: now,
                  ),
                ),
                if (todo.isDailyLog) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.lock_rounded,
                    size: 13,
                    color: secondary.withValues(alpha: 0.72),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    final isLockedOpenLog = todo.isDailyLog && todo.lockedCompleted != true;
    final accent = isLockedOpenLog
        ? secondary
        : todo.isFrog
        ? AppColors.frog
        : AppColors.quadrantColor(
            important: todo.isImportant,
            urgent: todo.isUrgent,
          );
    final titleStyle = _titleStyle.copyWith(
      color: isLockedOpenLog ? secondary : null,
    );
    final metas = _metaSpecs(todo, secondary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: todo.isDailyLog
                  ? secondary.withValues(alpha: 0.24)
                  : border,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(color: accent),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _horizontalPadding,
                  vertical: _verticalPadding,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _leadingSize,
                      height: _leadingSize,
                      child: IconButton(
                        key: ValueKey('calendar-complete-${todo.id}'),
                        tooltip: 'Hoàn thành',
                        onPressed: onCompleteTap,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        iconSize: 27,
                        icon: Icon(
                          todo.isDailyLog
                              ? Icons.lock_outline_rounded
                              : Icons.circle_outlined,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: _leadingGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TodoTimedTitle(
                            title: todo.title,
                            time: todo.time,
                            scheduledDate: todo.scheduledDate,
                            style: titleStyle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            now: now,
                          ),
                          if (metas.isNotEmpty) ...[
                            const SizedBox(height: _metaTopGap),
                            Wrap(
                              spacing: _metaSpacing,
                              runSpacing: _metaRunSpacing,
                              children: [
                                for (final meta in metas)
                                  _MiniMeta(
                                    icon: meta.icon,
                                    label: meta.label,
                                    color: meta.color,
                                  ),
                              ],
                            ),
                          ],
                        ],
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
}

class _MetaSpec {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaSpec(this.icon, this.label, this.color);
}

class _MiniMeta extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniMeta({
    required this.icon,
    required this.label,
    required this.color,
  });

  static const double iconSize = 12;
  static const double iconGap = 3;

  static TextStyle textStyle(Color color) =>
      TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: iconGap),
        Text(label, style: textStyle(color)),
      ],
    );
  }
}

class _CalendarEmptyState extends StatelessWidget {
  const _CalendarEmptyState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 96),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.event_available_outlined, size: 40, color: secondary),
            const SizedBox(height: 12),
            Text(
              'Ngày này chưa có todo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Các việc không có giờ và có giờ sẽ xuất hiện ở đây.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EffectiveIndicator {
  final bool visible;
  final int lineMinutesSinceMidnight;
  final int hiddenHourMarkMinute;
  final String label;

  const _EffectiveIndicator({
    required this.visible,
    required this.lineMinutesSinceMidnight,
    required this.hiddenHourMarkMinute,
    required this.label,
  });

  factory _EffectiveIndicator.from({
    required CalendarDayDetail detail,
    required DateTime now,
    required int startMinute,
    required int endMinute,
    required List<int> halfHourMarks,
  }) {
    final indicator = detail.currentTimeIndicator;
    final visible =
        indicator.visible && AppDateUtils.isSameDay(detail.date, now);
    if (!visible) {
      return const _EffectiveIndicator(
        visible: false,
        lineMinutesSinceMidnight: 0,
        hiddenHourMarkMinute: -1,
        label: '',
      );
    }
    final minute = (now.hour * 60 + now.minute)
        .clamp(startMinute, endMinute)
        .toInt();
    final hidden = _nearbyTimeMarkMinute(
      minute,
      startMinute,
      endMinute,
      halfHourMarks,
    );
    return _EffectiveIndicator(
      visible: true,
      lineMinutesSinceMidnight: minute,
      hiddenHourMarkMinute: hidden,
      label: AppDateUtils.formatTime(now),
    );
  }

  static int _nearbyTimeMarkMinute(
    int minute,
    int startMinute,
    int endMinute,
    List<int> halfHourMarks,
  ) {
    final nearest = ((minute + 15) ~/ 30) * 30;
    final distance = (nearest - minute).abs();
    if (distance >= 10 || nearest < startMinute || nearest > endMinute) {
      return -1;
    }
    if (nearest % 60 != 0 && !halfHourMarks.contains(nearest)) return -1;
    return nearest;
  }
}
