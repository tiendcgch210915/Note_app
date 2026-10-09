import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/dashboard_repository.dart';
import '../../models/dashboard.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_snack.dart';
import '../../utils/date_utils.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/clamp_text_scale.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/calendar_day_cell.dart';
import 'calendar_day_detail_screen.dart';

/// Cỡ chữ hệ thống tối đa mà ô lưới cố định chiều cao có thể chứa được.
const double _maxTextScale = 1.35;

/// Tab Lịch — dùng F-D3 calendar overview.
///
/// Layout: lịch sử thu gọn ở trên, grid chính 30 ngày với hôm nay ở dòng 3.
/// Past/today hiện điểm + tiến độ todos/habits, future hiện tổng todos/habits.
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
    showAppSnack(context, message, isError: true);
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
      return const AppSpinner();
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
    final secondary = context.appTextSecondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: AppSurface(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AppHaptics.selection();
                _toggleHistory();
              },
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    color: _historyExpanded ? context.appPrimary : secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _historyExpanded
                              ? '30 ngày trước đó'
                              : 'Xem 30 ngày trước đó',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _historyExpanded
                              ? 'Lịch sử trước vùng 30 ngày hiện tại'
                              : 'Lịch sử đang được thu gọn',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _historyExpanded ? 0.5 : 0,
                    duration: AppMotion.normal,
                    curve: AppMotion.curve,
                    child: Icon(Icons.expand_more_rounded, color: secondary),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              alignment: Alignment.topCenter,
              child: _historyExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: OutlinedButton.icon(
                            onPressed: _historyLoading
                                ? null
                                : _pickHistoryRange,
                            icon: const Icon(
                              Icons.date_range_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _historyRangeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  SliverPadding _buildDateGrid({
    required List<DateTime> dates,
    required EdgeInsetsGeometry padding,
  }) {
    // Chiều cao ô co giãn theo cỡ chữ hệ thống để nội dung không bị tràn.
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, _maxTextScale);
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 120 * scale,
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

    return ClampTextScale(
      maxScale: _maxTextScale,
      child: CalendarDayCell(
        date: date,
        isFuture: isFuture,
        isToday: AppDateUtils.isToday(date),
        score: isFuture ? null : (day?.score ?? 0),
        totalTodos: day?.totalTodos ?? 0,
        doneTodos: day?.doneTodos ?? 0,
        habitsTotal: day?.habitsTotal ?? 0,
        habitsCompleted: day?.habitsCompleted ?? 0,
        onTap: () => _openDayDetail(date),
      ),
    );
  }

  Future<void> _openDayDetail(DateTime date) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalendarDayDetailScreen(initialDate: date),
      ),
    );
    if (mounted) await _fetchMainWindow();
  }

  String get _historyRangeLabel {
    final from = _historyFrom ?? _defaultHistoryFrom;
    final to = _historyTo ?? _defaultHistoryTo;
    return '${AppDateUtils.formatDate(from)} - ${AppDateUtils.formatDate(to)}';
  }
}
