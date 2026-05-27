import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/run.dart';
import '../../theme/app_colors.dart';
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
  List<Run> _runs = [];
  String? _cursor;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final res = await ChecklistsRepository.instance.listRuns(limit: 20);
      if (!mounted) return;
      setState(() {
        _runs = res.items;
        _cursor = res.nextCursor;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.vnMessage)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
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
      body: _loading && _runs.isEmpty
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
                            subtitle: Text(AppDateUtils.formatRelative(r.startedAt)),
                            trailing: _chip(r.status),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => RunDetailScreen(runId: r.id)),
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
      child: Text(s.label,
          style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
    );
  }
}
