import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/run.dart';
import '../../theme/app_colors.dart';
import '../../utils/checklist_local_events.dart';
import '../../utils/date_utils.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/run_status_chip.dart';
import 'run_detail_screen.dart';

/// Standalone screen liệt kê toàn bộ runs (entry từ ngoài ChecklistsScreen).
class RunsHistoryScreen extends StatefulWidget {
  const RunsHistoryScreen({super.key});

  @override
  State<RunsHistoryScreen> createState() => _RunsHistoryScreenState();
}

class _RunsHistoryScreenState extends State<RunsHistoryScreen> {
  static const _pageSize = 20;

  List<Run> _runs = [];
  String? _cursor;

  /// Đã đọc xong cache Drift ít nhất một lần (kể cả khi cache rỗng).
  bool _localLoaded = false;
  int _inFlight = 0;

  bool get _refreshing => _inFlight > 0;

  @override
  void initState() {
    super.initState();
    ChecklistLocalEvents.instance.addListener(_onLocalChanged);
    _refresh();
  }

  @override
  void dispose() {
    ChecklistLocalEvents.instance.removeListener(_onLocalChanged);
    super.dispose();
  }

  void _onLocalChanged() => unawaited(_loadLocal());

  /// Hiện ngay lịch sử đã lưu trong SQLite, sau đó mới hỏi server.
  Future<void> _refresh() async {
    await _loadLocal();
    await _revalidate();
  }

  Future<void> _loadLocal() async {
    // Giữ nguyên số dòng đã cuộn tới để cập nhật nền không làm danh sách ngắn lại.
    final res = await ChecklistsRepository.instance.listRunsLocal(
      limit: math.max(_pageSize, _runs.length),
    );
    if (!mounted) return;
    setState(() {
      _runs = res.items;
      _localLoaded = true;
    });
  }

  Future<void> _revalidate() async {
    if (!mounted) return;
    setState(() => _inFlight++);
    try {
      final res = await ChecklistsRepository.instance.listRuns(
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _runs = res.items;
        _cursor = res.nextCursor;
        _localLoaded = true;
      });
    } on ApiException catch (e) {
      if (mounted && (_runs.isEmpty || !e.isRetryable)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.vnMessage)));
      }
    } finally {
      if (mounted) setState(() => _inFlight--);
    }
  }

  Future<void> _loadMore() async {
    if (_cursor == null) return;
    try {
      final res = await ChecklistsRepository.instance.listRuns(
        cursor: _cursor,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _runs = [..._runs, ...res.items];
        _cursor = res.nextCursor;
      });
    } catch (_) {}
  }

  Future<void> _deleteRun(Run run) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa khỏi lịch sử?'),
        content: const Text('Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xóa', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ChecklistsRepository.instance.deleteRun(run.id);
      setState(() => _runs.removeWhere((r) => r.id == run.id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử run')),
      body: !_localLoaded || (_refreshing && _runs.isEmpty)
          ? const AppSpinner()
          : _runs.isEmpty
          ? const EmptyState(icon: Icons.history, title: 'Chưa có run nào')
          : RefreshIndicator(
              onRefresh: _refresh,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) {
                    _loadMore();
                  }
                  return false;
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _runs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final r = _runs[i];
                    return AppSurface(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      onTap: () async {
                        await openChecklistRun(context, r);
                        _refresh();
                      },
                      onLongPress: () => _deleteRun(r),
                      child: Row(
                        children: [
                          Icon(
                            Icons.checklist_rounded,
                            color: context.appPrimary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.displayName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _runSubtitle(r),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.appTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          RunStatusChip(status: r.status),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

String _runSubtitle(Run run) {
  final started = AppDateUtils.formatRelative(run.startedAt);
  final durationMs = run.durationMs;
  if (durationMs == null) return started;
  return '$started - Thời lượng: ${_formatDurationMs(durationMs)}';
}

String _formatDurationMs(int durationMs) {
  final totalSeconds = Duration(milliseconds: durationMs).inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours == 0) return '$mm:$ss';
  final hh = hours.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}
