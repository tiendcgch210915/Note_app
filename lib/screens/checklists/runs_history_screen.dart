import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/run.dart';
import '../../theme/app_colors.dart';
import '../../utils/checklist_local_events.dart';
import '../../utils/date_utils.dart';
import '../../widgets/empty_state.dart';
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
          ? const Center(child: CircularProgressIndicator())
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
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final r = _runs[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.checklist),
                        title: Text(r.displayName),
                        subtitle: Text(_runSubtitle(r)),
                        trailing: _chip(r.status),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RunDetailScreen(runId: r.id),
                            ),
                          );
                          _refresh();
                        },
                        onLongPress: () => _deleteRun(r),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  Widget _chip(RunStatus s) {
    Color c;
    switch (s) {
      case RunStatus.inProgress:
        c = AppColors.success;
        break;
      case RunStatus.completed:
        c = AppColors.textSecondary;
        break;
      case RunStatus.abandoned:
        c = AppColors.warning;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        s.label,
        style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
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
