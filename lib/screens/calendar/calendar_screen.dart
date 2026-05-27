import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/dashboard_repository.dart';
import '../../models/dashboard.dart';
import '../../utils/date_utils.dart';
import '../../widgets/calendar_day_cell.dart';

/// Tab Lịch — dùng F-D3 calendar overview.
///
/// Layout: today góc trái trên, scroll xuống = quá khứ. Past/today hiện score,
/// future hiện total_todos.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final Map<DateTime, CalendarDay> _days = {};
  DateTime? _oldestFetched;
  bool _loading = false;
  bool _loadingMore = false;

  DateTime get _today => AppDateUtils.dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _fetchRange(_today.subtract(const Duration(days: 21)), _today.add(const Duration(days: 8)));
  }

  Future<void> _fetchRange(DateTime from, DateTime to) async {
    setState(() => _loading = true);
    try {
      final data = await DashboardRepository.instance.calendar(from: from, to: to);
      if (!mounted) return;
      setState(() {
        _days.addAll(data);
        if (_oldestFetched == null || from.isBefore(_oldestFetched!)) {
          _oldestFetched = from;
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.vnMessage)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMorePast() async {
    if (_loadingMore || _oldestFetched == null) return;
    setState(() => _loadingMore = true);
    final to = _oldestFetched!.subtract(const Duration(days: 1));
    final from = to.subtract(const Duration(days: 29));
    try {
      final data = await DashboardRepository.instance.calendar(from: from, to: to);
      if (!mounted) return;
      setState(() {
        _days.addAll(data);
        _oldestFetched = from;
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Ordered: today first, then today+1..+8, then today-1, -2, ..., _oldestFetched.
  List<DateTime> get _dates {
    final list = <DateTime>[_today];
    for (var i = 1; i <= 8; i++) {
      list.add(_today.add(Duration(days: i)));
    }
    if (_oldestFetched != null) {
      var d = _today.subtract(const Duration(days: 1));
      while (!d.isBefore(_oldestFetched!)) {
        list.add(d);
        d = d.subtract(const Duration(days: 1));
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _days.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final dates = _dates;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) {
              _loadMorePast();
            }
            return false;
          },
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: dates.length + (_loadingMore ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i >= dates.length) {
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              }
              final date = dates[i];
              final day = _days[date];
              final isToday = AppDateUtils.isToday(date);
              return CalendarDayCell(
                date: date,
                isToday: isToday,
                score: day?.score,
                todoCount: day?.score == null ? (day?.totalTodos ?? 0) : null,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Mở ${AppDateUtils.formatDate(date)} (demo)'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          top: 8,
          child: Material(
            color: Colors.transparent,
            child: IconButton(
              icon: const Icon(Icons.today),
              tooltip: 'Refresh',
              onPressed: () => _fetchRange(_today.subtract(const Duration(days: 21)), _today.add(const Duration(days: 8))),
            ),
          ),
        ),
      ],
    );
  }
}
