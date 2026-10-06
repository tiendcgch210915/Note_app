import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/todo_time_utils.dart';

class TodoTimedTitle extends StatelessWidget {
  final String title;
  final String? time;
  final DateTime? scheduledDate;
  final TextStyle? style;
  final String prefix;
  final int? maxLines;
  final TextOverflow overflow;
  final DateTime? now;

  const TodoTimedTitle({
    super.key,
    required this.title,
    required this.time,
    required this.scheduledDate,
    this.style,
    this.prefix = '',
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(style);
    final timeLabel = formatTodoTime(time);
    if (timeLabel == null) {
      return Text(
        '$prefix$title',
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    if (now != null) {
      return _buildTimedText(baseStyle, timeLabel, now!);
    }
    return AnimatedBuilder(
      animation: _TodoMinuteTicker.instance,
      builder: (context, _) =>
          _buildTimedText(baseStyle, timeLabel, _TodoMinuteTicker.instance.now),
    );
  }

  Widget _buildTimedText(
    TextStyle baseStyle,
    String timeLabel,
    DateTime current,
  ) {
    final state = todoTimeState(
      scheduledDate: scheduledDate,
      time: time,
      now: current,
    );
    final timeColor = switch (state) {
      TodoTimeState.upcoming => AppColors.success,
      TodoTimeState.near => AppColors.warning,
      TodoTimeState.overdue => AppColors.danger,
      null => baseStyle.color,
    };

    return RichText(
      maxLines: maxLines,
      overflow: overflow,
      text: TextSpan(
        style: baseStyle,
        children: [
          if (prefix.isNotEmpty) TextSpan(text: prefix),
          TextSpan(
            text: '[$timeLabel]',
            style: baseStyle.copyWith(color: timeColor),
          ),
          const TextSpan(text: ' '),
          TextSpan(text: title),
        ],
      ),
    );
  }
}

class _TodoMinuteTicker extends ChangeNotifier {
  _TodoMinuteTicker._();

  static final _TodoMinuteTicker instance = _TodoMinuteTicker._();

  DateTime now = DateTime.now();
  Timer? _timer;

  @override
  void addListener(VoidCallback listener) {
    final shouldStart = !hasListeners;
    super.addListener(listener);
    if (shouldStart) _scheduleNextMinute();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _scheduleNextMinute() {
    _timer?.cancel();
    now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    ).add(const Duration(milliseconds: 50));
    _timer = Timer(nextMinute.difference(now), () {
      now = DateTime.now();
      notifyListeners();
      if (hasListeners) _scheduleNextMinute();
    });
  }
}
