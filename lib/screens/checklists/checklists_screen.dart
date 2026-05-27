import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/run.dart';
import '../../models/template.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../widgets/empty_state.dart';
import 'run_detail_screen.dart';
import 'template_create_screen.dart';
import 'template_detail_screen.dart';

class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  List<Template> _templates = [];
  List<Run> _runs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final tplFut = ChecklistsRepository.instance.listTemplates(scope: 'all');
      final runsFut = ChecklistsRepository.instance.listRuns(limit: 20);
      final results = await Future.wait([tplFut, runsFut]);
      if (!mounted) return;
      final runsRes = results[1] as ({List<Run> items, String? nextCursor});
      setState(() {
        _templates = results[0] as List<Template>;
        _runs = runsRes.items;
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checklist'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Templates'),
            Tab(text: 'Lịch sử'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (ctx, _) => _tab.index == 0
            ? FloatingActionButton.extended(
                onPressed: () async {
                  final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const TemplateCreateScreen()),
                  );
                  if (created == true && mounted) _refresh();
                },
                icon: const Icon(Icons.add),
                label: const Text('Template'),
              )
            : const SizedBox.shrink(),
      ),
      body: _loading && _templates.isEmpty && _runs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _TemplatesTab(templates: _templates, onChanged: _refresh),
                _RunsTab(runs: _runs, onDelete: _deleteRun, onChanged: _refresh),
              ],
            ),
    );
  }
}

class _TemplatesTab extends StatelessWidget {
  final List<Template> templates;
  final VoidCallback onChanged;
  const _TemplatesTab({required this.templates, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return const EmptyState(icon: Icons.checklist, title: 'Chưa có template nào');
    }
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: templates.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final t = templates[i];
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(Template.iconFor(t.icon), color: AppColors.primary),
              title: Row(
                children: [
                  Expanded(child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (t.isSystem)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Hệ thống',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              subtitle: Text('Dùng ${t.timesUsed} lần'),
              trailing: TextButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Bắt đầu'),
                onPressed: () async {
                  try {
                    final res = await ChecklistsRepository.instance
                        .startRun(templateId: t.id, name: t.title);
                    if (!context.mounted) return;
                    onChanged();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => RunDetailScreen(runId: res.run.id)),
                    );
                  } on ApiException catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.vnMessage)),
                      );
                    }
                  }
                },
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => TemplateDetailScreen(templateId: t.id)),
                );
                onChanged();
              },
            ),
          );
        },
      ),
    );
  }
}

class _RunsTab extends StatelessWidget {
  final List<Run> runs;
  final void Function(Run) onDelete;
  final VoidCallback onChanged;
  const _RunsTab({required this.runs, required this.onDelete, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return const EmptyState(icon: Icons.history, title: 'Chưa có run nào');
    }
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: runs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final r = runs[i];
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(r.displayName),
              subtitle: Text('Bắt đầu: ${AppDateUtils.formatRelative(r.startedAt)}'),
              trailing: _RunStatusChip(status: r.status),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RunDetailScreen(runId: r.id)),
                );
                onChanged();
              },
              onLongPress: () => onDelete(r),
            ),
          );
        },
      ),
    );
  }
}

class _RunStatusChip extends StatelessWidget {
  final RunStatus status;
  const _RunStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status) {
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
      child: Text(status.label,
          style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
    );
  }
}
