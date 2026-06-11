import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/run.dart';
import '../../models/run_item.dart';
import '../../theme/app_colors.dart';
import '../../widgets/primary_button.dart';

/// RunDetailScreen — fetch run + items, update items, complete/abandon.
/// EXP 8: Thêm note cho RunItem qua Dialog TextField.
class RunDetailScreen extends StatefulWidget {
  final String runId;
  const RunDetailScreen({super.key, required this.runId});

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  Run? _run;
  List<RunItem> _items = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ChecklistsRepository.instance.getRun(widget.runId);
      if (!mounted) return;
      setState(() {
        _run = res.run;
        _items = res.items;
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(RunItem item) async {
    final newStatus = item.status == RunItemStatus.done
        ? RunItemStatus.pending
        : RunItemStatus.done;
    try {
      final updated = await ChecklistsRepository.instance.updateRunItem(
        widget.runId,
        item.id,
        status: newStatus.backendValue,
        note: item.note,
      );
      setState(() {
        _items = _items.map((i) => i.id == item.id ? updated : i).toList();
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _showItemSheet(RunItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Đánh dấu hoàn thành'),
              onTap: () => Navigator.of(ctx).pop('done'),
            ),
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: const Text('Bỏ qua'),
              onTap: () => Navigator.of(ctx).pop('skipped'),
            ),
            ListTile(
              leading: const Icon(Icons.note_outlined),
              title: const Text('Thêm/sửa ghi chú'),
              onTap: () => Navigator.of(ctx).pop('note'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'done' || action == 'skipped') {
      try {
        final newStatus = action == 'done'
            ? RunItemStatus.done
            : RunItemStatus.skipped;
        final updated = await ChecklistsRepository.instance.updateRunItem(
          widget.runId,
          item.id,
          status: newStatus.backendValue,
          note: item.note,
        );
        setState(() {
          _items = _items.map((i) => i.id == item.id ? updated : i).toList();
        });
      } on ApiException catch (e) {
        if (mounted) _showError(e.vnMessage);
      }
    } else if (action == 'note') {
      _editNote(item);
    }
  }

  // EXP 8 — Note Dialog
  Future<void> _editNote(RunItem item) async {
    final ctrl = TextEditingController(text: item.note ?? '');
    final newNote = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghi chú'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Tối đa 1000 ký tự'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (newNote == null) return;
    try {
      final updated = await ChecklistsRepository.instance.updateRunItem(
        widget.runId,
        item.id,
        status: item.status.backendValue,
        note: newNote.isEmpty ? null : newNote,
      );
      setState(() {
        _items = _items.map((i) => i.id == item.id ? updated : i).toList();
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _complete() async {
    try {
      await ChecklistsRepository.instance.completeRun(widget.runId);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Hoàn tất run! 🎉')));
      }
    } on ApiException catch (e) {
      if (e.code == 'incomplete_required' && mounted) {
        _showError('Còn bước bắt buộc chưa hoàn thành');
      } else if (mounted) {
        _showError(e.vnMessage);
      }
    }
  }

  Future<void> _confirmAbandon() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy bỏ run?'),
        content: const Text('Tiến độ hiện tại sẽ được lưu là Abandoned.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Không'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Hủy bỏ',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ChecklistsRepository.instance.abandonRun(widget.runId);
      if (mounted) Navigator.of(context).pop();
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
    if (_loading && _run == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_run == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Không tìm thấy run')),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark ? AppColors.dividerDark : AppColors.divider;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final done = _items.where((i) => i.status == RunItemStatus.done).length;
    final requiredPending = _items
        .where((i) => i.isRequired && i.status == RunItemStatus.pending)
        .length;
    final progress = _items.isEmpty
        ? 0.0
        : (done / _items.length).clamp(0.0, 1.0);
    final canComplete =
        requiredPending == 0 && _run!.status == RunStatus.inProgress;

    return Scaffold(
      appBar: AppBar(
        title: Text(_run!.name ?? 'Run'),
        actions: [
          if (_run!.status == RunStatus.inProgress)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _confirmAbandon,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$done/${_items.length} bước hoàn thành',
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: divider,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: _items.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: divider),
                itemBuilder: (ctx, i) => _itemRow(_items[i], secondary),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _run!.status == RunStatus.inProgress
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!canComplete && requiredPending > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Còn $requiredPending bước bắt buộc',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ),
                    PrimaryButton(
                      label: 'Hoàn tất checklist',
                      icon: Icons.check,
                      onPressed: canComplete ? _complete : null,
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _itemRow(RunItem it, Color secondary) {
    final isDone = it.status == RunItemStatus.done;
    final isSkipped = it.status == RunItemStatus.skipped;
    return InkWell(
      onTap: () => _toggle(it),
      onLongPress: () => _showItemSheet(it),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isSkipped)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Bỏ qua',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Icon(
                    isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isDone ? AppColors.primary : secondary,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    it.title,
                    style: TextStyle(
                      fontSize: 15,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      color: isDone || isSkipped ? secondary : null,
                      fontStyle: isSkipped ? FontStyle.italic : null,
                    ),
                  ),
                ),
                if (!it.isRequired)
                  Text(
                    'Tùy chọn',
                    style: TextStyle(fontSize: 11, color: secondary),
                  ),
              ],
            ),
            if (it.note != null && it.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 4),
                child: Text(
                  '📝 ${it.note}',
                  style: TextStyle(
                    fontSize: 12,
                    color: secondary,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
