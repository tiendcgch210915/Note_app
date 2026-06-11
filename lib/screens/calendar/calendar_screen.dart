import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/dashboard_repository.dart';
import '../../models/dashboard.dart';
import '../../utils/date_utils.dart';
import '../../widgets/calendar_day_cell.dart';

/// Tab Lịch — dùng F-D3 calendar overview.
///
/// Layout: lịch sử thu gọn ở trên, grid chính 30 ngày với hôm nay ở dòng 3.
/// Past/today hiện score + tiến độ todos/habits, future hiện tổng todos/habits.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final Map<DateTime, CalendarDay> _days = {};
  DateTime? _historyFrom;
  DateTime? _historyTo;
  bool _loadingMainWindow = false;
  bool _historyExpanded = false;
  bool _historyLoading = false;

  DateTime get _today => AppDateUtils.dateOnly(DateTime.now());
  DateTime get _mainWindowFrom => _today.subtract(const Duration(days: 6));
  DateTime get _mainWindowTo => _mainWindowFrom.add(const Duration(days: 29));
  DateTime get _defaultHistoryFrom =>
      _mainWindowFrom.subtract(const Duration(days: 30));
  DateTime get _defaultHistoryTo =>
      _mainWindowFrom.subtract(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _fetchMainWindow();
  }

  Future<void> _fetchMainWindow() async {
    setState(() => _loadingMainWindow = true);
    try {
      final data = await DashboardRepository.instance.calendar(
        from: _mainWindowFrom,
        to: _mainWindowTo,
      );
      if (!mounted) return;
      setState(() {
        _days.addAll(data);
      });
    } on ApiException catch (e) {
      _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loadingMainWindow = false);
    }
  }

  Future<void> _fetchHistoryRange(DateTime from, DateTime to) async {
    final rangeFrom = AppDateUtils.dateOnly(from);
    final rangeTo = AppDateUtils.dateOnly(to);
    if (rangeTo.isBefore(rangeFrom)) return;

    setState(() {
      _historyFrom = rangeFrom;
      _historyTo = rangeTo;
      _historyLoading = true;
    });

    try {
      final data = await DashboardRepository.instance.calendar(
        from: rangeFrom,
        to: rangeTo,
      );
      if (!mounted) return;
      setState(() {
        _days.addAll(data);
      });
    } on ApiException catch (e) {
      _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _toggleHistory() async {
    if (_historyExpanded) {
      setState(() => _historyExpanded = false);
      return;
    }

    setState(() => _historyExpanded = true);
    await _fetchHistoryRange(_defaultHistoryFrom, _defaultHistoryTo);
  }

  Future<void> _pickHistoryRange() async {
    if (!_historyExpanded) return;

    final lastHistoryDate = _defaultHistoryTo;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: _today.subtract(const Duration(days: 365 * 5)),
      lastDate: lastHistoryDate,
      currentDate: lastHistoryDate,
      initialDateRange: DateTimeRange(
        start: _historyFrom ?? _defaultHistoryFrom,
        end: _historyTo ?? _defaultHistoryTo,
      ),
      helpText: 'Chọn khoảng lịch sử',
      cancelText: 'Hủy',
      confirmText: 'Áp dụng',
      saveText: 'Áp dụng',
    );
    if (picked == null) return;

    await _fetchHistoryRange(picked.start, picked.end);
  }

  Future<void> _refresh() async {
    await _fetchMainWindow();
    if (_historyExpanded) {
      await _fetchHistoryRange(
        _historyFrom ?? _defaultHistoryFrom,
        _historyTo ?? _defaultHistoryTo,
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<DateTime> get _mainWindowDates {
    return List.generate(30, (i) => _mainWindowFrom.add(Duration(days: i)));
  }

  List<DateTime> get _historyDates {
    final from = _historyFrom;
    final to = _historyTo;
    if (from == null || to == null) return const [];

    final list = <DateTime>[];
    var d = to;
    while (!d.isBefore(from)) {
      list.add(d);
      d = d.subtract(const Duration(days: 1));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingMainWindow && _days.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHistoryHeader(context)),
          if (_historyExpanded && _historyLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ),
          if (_historyExpanded)
            _buildDateGrid(
              dates: _historyDates,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            ),
          _buildDateGrid(
            dates: _mainWindowDates,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _toggleHistory,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history,
                        color: _historyExpanded
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _historyExpanded
                                  ? '30 ngày trước đó'
                                  : 'Xem 30 ngày trước đó',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _historyExpanded
                                  ? 'Lịch sử trước vùng 30 ngày hiện tại'
                                  : 'Lịch sử đang được thu gọn',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _historyExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              if (_historyExpanded) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: OutlinedButton.icon(
                      onPressed: _historyLoading ? null : _pickHistoryRange,
                      icon: const Icon(Icons.filter_alt_outlined, size: 18),
                      label: Text(
                        _historyRangeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  SliverPadding _buildDateGrid({
    required List<DateTime> dates,
    required EdgeInsetsGeometry padding,
  }) {
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _buildDayCell(dates[i]),
          childCount: dates.length,
        ),
      ),
    );
  }

  Widget _buildDayCell(DateTime date) {
    final day = _days[date];
    final isFuture = AppDateUtils.isFuture(date);

    return CalendarDayCell(
      date: date,
      isFuture: isFuture,
      isToday: AppDateUtils.isToday(date),
      score: isFuture ? null : (day?.score ?? 0),
      totalTodos: day?.totalTodos ?? 0,
      doneTodos: day?.doneTodos ?? 0,
      habitsTotal: day?.habitsTotal ?? 0,
      habitsCompleted: day?.habitsCompleted ?? 0,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mở ${AppDateUtils.formatDate(date)} (demo)'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
    );
  }

  String get _historyRangeLabel {
    final from = _historyFrom ?? _defaultHistoryFrom;
    final to = _historyTo ?? _defaultHistoryTo;
    return '${AppDateUtils.formatDate(from)} - ${AppDateUtils.formatDate(to)}';
  }
}
