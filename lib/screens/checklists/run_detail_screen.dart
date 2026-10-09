import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/checklists_repository.dart';
import '../../models/run.dart';
import '../../models/run_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/active_session_guard.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_snack.dart';
import '../../utils/checklist_local_events.dart';
import '../../utils/checklist_session_controller.dart';
import '../../widgets/app_list_section.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';

/// Bắt đầu (hoặc tiếp tục) lượt chạy của [templateId] và đăng ký nó làm phiên
/// đang làm, để đồng hồ đếm xuôi và banner toàn app hoạt động.
///
/// Trả về id run cần mở, hoặc `null` nếu bị chặn vì đang làm việc khác (người
/// dùng đã được báo). Bắt đầu lại đúng checklist đang chạy thì trả về chính run
/// đó. Ném [ApiException] nếu không tạo được run.
Future<String?> beginChecklistRun(
  BuildContext context, {
  required String templateId,
  String? name,
}) async {
  final controller = ChecklistSessionController.instance;
  final active = controller.session.value;
  if (active != null && active.templateId == templateId) return active.runId;
  if (!await ensureNoActiveSession(context)) return null;
  final res = await ChecklistsRepository.instance.startRun(
    templateId: templateId,
    name: name,
  );
  if (!controller.start(res.run, items: res.items)) {
    // Có phiên khác chen vào giữa lúc đang tạo run.
    if (context.mounted) await ensureNoActiveSession(context);
    return null;
  }
  return res.run.id;
}

/// Mở một run từ danh sách. Run đang chạy mà chưa phải phiên hiện tại thì
/// phải xin vào phiên trước: đang làm việc khác thì bị chặn và báo người dùng.
/// Hoàn thành khi màn hình chi tiết đóng lại.
Future<void> openChecklistRun(BuildContext context, Run run) async {
  final controller = ChecklistSessionController.instance;
  if (run.status == RunStatus.inProgress && !controller.isActiveFor(run.id)) {
    if (!await ensureNoActiveSession(context)) return;
    if (!controller.start(run)) {
      if (context.mounted) await ensureNoActiveSession(context);
      return;
    }
  }
  if (!context.mounted) return;
  await openRunDetail(Navigator.of(context), run.id);
}

/// Mở màn hình chi tiết run. Luôn mở qua hàm này (đừng `Navigator.push` thẳng):
/// nó đặt cờ "đang mở" TRƯỚC khi push để banner ẩn ngay, không bị nháy khi màn
/// hình trượt vào. Hoàn thành khi màn hình đóng; với [replace] là khi màn hình
/// mới đóng, dù màn hình gọi đã bị thay thế.
Future<void> openRunDetail(
  NavigatorState navigator,
  String runId, {
  bool replace = false,
}) async {
  final controller = ChecklistSessionController.instance;
  controller.screenOpened(runId);
  try {
    final route = MaterialPageRoute<void>(
      builder: (_) => RunDetailScreen(runId: runId),
    );
    if (replace) {
      await navigator.pushReplacement<void, void>(route);
    } else {
      await navigator.push<void>(route);
    }
  } finally {
    controller.screenClosed(runId);
  }
}

/// Quay lại checklist đang chạy ngầm (từ banner toàn app).
Future<void> resumeChecklistSession() async {
  final navigator = rootNavigatorKey.currentState;
  final session = ChecklistSessionController.instance.session.value;
  if (navigator == null || session == null) return;
  await openRunDetail(navigator, session.runId);
}

/// RunDetailScreen — fetch run + items, update items, complete/abandon.
/// EXP 8: Thêm note cho RunItem qua Dialog TextField.
///
/// Rời màn hình bằng nút back không kết thúc lượt chạy: đồng hồ vẫn đếm và
/// banner toàn app hiện ra. Chỉ "Hoàn tất" hoặc "Hủy bỏ" mới kết thúc phiên.
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
  String? _loadError;
  bool _doneItemsExpanded = false;
  Timer? _timer;

  /// Đồng hồ chạy bằng ValueNotifier: mỗi giây chỉ vẽ lại viên thuốc giờ,
  /// không dựng lại cả danh sách bước.
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _elapsed.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await ChecklistsRepository.instance.getRun(widget.runId);
      if (!mounted) return;
      setState(() {
        _run = res.run;
        _items = res.items;
      });
      _elapsed.value = _elapsedForRun(res.run);
      _startTimerIfNeeded(res.run);
      _endSessionIfRunFinished(res.run);
      unawaited(_revalidate());
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_run == null) {
        setState(() => _loadError = e.vnMessage);
      } else {
        _showError(e.vnMessage);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Bản đang hiện lấy từ Drift; hỏi server xem có thay đổi mới (từ thiết bị
  /// khác) không và vẽ lại ngay nếu có. Lỗi thì giữ nguyên bản cache.
  Future<void> _revalidate() async {
    try {
      final res = await ChecklistsRepository.instance.refreshRun(widget.runId);
      if (!mounted) return;
      setState(() {
        _run = res.run;
        _items = res.items;
      });
      _elapsed.value = _elapsedForRun(res.run);
      _startTimerIfNeeded(res.run);
      _endSessionIfRunFinished(res.run);
    } on ApiException {
      // Giữ bản cache đang hiển thị.
    }
  }

  /// Run đã hoàn tất/hủy ở nơi khác (thiết bị khác, sync pull) thì phiên
  /// "đang làm" của nó không còn nghĩa — gỡ banner và mở khóa việc mới.
  void _endSessionIfRunFinished(Run run) {
    if (run.status == RunStatus.inProgress) return;
    ChecklistSessionController.instance.finish(runId: run.id);
  }

  /// Cập nhật tiến độ trên banner theo Drift sau khi ghi một bước. Chạy cả khi
  /// màn hình đã đóng giữa chừng.
  void _publishProgress() {
    unawaited(ChecklistSessionController.instance.refreshFromLocal());
  }

  Future<void> _toggle(RunItem item) async {
    final newStatus = item.status == RunItemStatus.done
        ? RunItemStatus.pending
        : RunItemStatus.done;
    if (newStatus == RunItemStatus.done) {
      AppHaptics.medium();
    } else {
      AppHaptics.selection();
    }
    try {
      final updated = await ChecklistsRepository.instance.updateRunItem(
        widget.runId,
        item.id,
        status: newStatus.backendValue,
        note: item.note,
      );
      _publishProgress();
      if (!mounted) return;
      setState(() {
        _items = _items.map((i) => i.id == item.id ? updated : i).toList();
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _showItemSheet(RunItem item) async {
    AppHaptics.medium();
    final action = await showAppSheet<String>(
      context: context,
      builder: (ctx) => AppSheetScaffold(
        title: item.title,
        child: AppListSection(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          dividerIndent: AppListSection.iconIndent,
          children: [
            AppListTile(
              icon: Icons.check_circle_rounded,
              iconColor: AppColors.success,
              title: 'Đánh dấu hoàn thành',
              showChevron: false,
              onTap: () => Navigator.of(ctx).pop('done'),
            ),
            AppListTile(
              icon: Icons.skip_next_rounded,
              iconColor: AppColors.warning,
              title: 'Bỏ qua',
              showChevron: false,
              onTap: () => Navigator.of(ctx).pop('skipped'),
            ),
            AppListTile(
              icon: Icons.sticky_note_2_rounded,
              iconColor: AppColors.tagAmber,
              title: 'Thêm/sửa ghi chú',
              showChevron: false,
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
        _publishProgress();
        if (!mounted) return;
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
    final newNote = await showAppTextInputDialog(
      context,
      title: 'Ghi chú',
      hintText: 'Tối đa 1000 ký tự',
      initialText: item.note ?? '',
      maxLines: 3,
    );
    if (newNote == null) return;
    try {
      final updated = await ChecklistsRepository.instance.updateRunItem(
        widget.runId,
        item.id,
        status: item.status.backendValue,
        note: newNote.isEmpty ? null : newNote,
      );
      if (!mounted) return;
      setState(() {
        _items = _items.map((i) => i.id == item.id ? updated : i).toList();
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _complete() async {
    try {
      await ChecklistsRepository.instance.completeRun(
        widget.runId,
        durationMs: _currentDurationMs(),
      );
      _timer?.cancel();
      _finishSession();
      if (mounted) {
        AppHaptics.medium();
        Navigator.of(context).pop();
        showAppSnack(context, 'Hoàn tất run! 🎉');
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
    final confirm = await showAppConfirmDialog(
      context,
      title: 'Hủy bỏ run?',
      message: 'Tiến độ hiện tại sẽ được lưu là "Đã hủy".',
      confirmLabel: 'Hủy bỏ',
      cancelLabel: 'Không',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    try {
      await ChecklistsRepository.instance.abandonRun(widget.runId);
      _timer?.cancel();
      _finishSession();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  /// Run đã chốt (hoàn tất/hủy): kết thúc phiên để gỡ banner, mở khóa việc mới,
  /// và báo các danh sách run đang mở đọc lại trạng thái từ Drift.
  void _finishSession() {
    ChecklistSessionController.instance.finish(runId: widget.runId);
    ChecklistLocalEvents.instance.notifyChanged();
  }

  void _showError(String msg) {
    showAppSnack(context, msg, isError: true);
  }

  void _startTimerIfNeeded(Run run) {
    _timer?.cancel();
    _timer = null;
    if (run.status != RunStatus.inProgress) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = _run;
      if (!mounted || current == null) return;
      _elapsed.value = _elapsedForRun(current);
    });
  }

  Duration _elapsedForRun(Run run) {
    if (run.status == RunStatus.completed && run.durationMs != null) {
      return Duration(milliseconds: run.durationMs!);
    }
    if (run.status != RunStatus.inProgress) return Duration.zero;
    final elapsed = DateTime.now().toUtc().difference(run.startedAt.toUtc());
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  int? _currentDurationMs() {
    final run = _run;
    if (run == null || run.status != RunStatus.inProgress) return null;
    final elapsed = _elapsedForRun(run).inMilliseconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _run == null) {
      return Scaffold(appBar: AppBar(), body: const AppSpinner());
    }
    if (_run == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _loadError != null
            ? AppErrorState(message: _loadError!, onRetry: _load)
            : const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Không tìm thấy run',
              ),
      );
    }
    final divider = context.appDivider;
    final secondary = context.appTextSecondary;
    final done = _items.where((i) => i.status == RunItemStatus.done).length;
    final requiredPending = _items
        .where((i) => i.isRequired && i.status == RunItemStatus.pending)
        .length;
    final progress = _items.isEmpty
        ? 0.0
        : (done / _items.length).clamp(0.0, 1.0);
    final canComplete =
        requiredPending == 0 && _run!.status == RunStatus.inProgress;
    final activeItems = _items
        .where((item) => item.status != RunItemStatus.done)
        .toList();
    final doneItems = _items
        .where((item) => item.status == RunItemStatus.done)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_run!.name ?? 'Run'),
        actions: [
          if (_run!.status == RunStatus.inProgress)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Hủy bỏ run',
              onPressed: _confirmAbandon,
            ),
        ],
      ),
      // Tiêu đề tiến độ nằm trong chính danh sách cuộn: màn thấp / chữ lớn
      // không còn bị cột cố định chiếm hết chỗ.
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$done/${_items.length} bước hoàn thành',
                          style: TextStyle(fontSize: 13, color: secondary),
                        ),
                      ),
                      _RunTimerPill(
                        elapsed: _elapsed,
                        isRunning: _run!.status == RunStatus.inProgress,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: AppMotion.slow,
                    curve: AppMotion.curve,
                    builder: (context, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        backgroundColor: divider,
                        valueColor: AlwaysStoppedAnimation(context.appPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ..._itemRows(activeItems, secondary, divider),
            if (doneItems.isNotEmpty) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AppHaptics.selection();
                  setState(() => _doneItemsExpanded = !_doneItemsExpanded);
                },
                child: SectionHeader(
                  label: 'Đã xong (${doneItems.length})',
                  leading: SectionHeader.dot(AppColors.success),
                  trailing: AnimatedRotation(
                    turns: _doneItemsExpanded ? 0.5 : 0,
                    duration: AppMotion.normal,
                    curve: AppMotion.curve,
                    child: Icon(Icons.expand_more_rounded, color: secondary),
                  ),
                ),
              ),
              AnimatedSize(
                duration: AppMotion.normal,
                curve: AppMotion.curve,
                alignment: Alignment.topCenter,
                child: _doneItemsExpanded
                    ? Column(children: _itemRows(doneItems, secondary, divider))
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _run!.status == RunStatus.inProgress
          ? Container(
              decoration: BoxDecoration(
                color: context.appBackground,
                border: Border(top: BorderSide(color: divider, width: 0.5)),
              ),
              child: SafeArea(
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
                        icon: Icons.check_rounded,
                        onPressed: canComplete ? _complete : null,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }

  List<Widget> _itemRows(List<RunItem> items, Color secondary, Color divider) {
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        widgets.add(Divider(height: 0.5, indent: 52, color: divider));
      }
      widgets.add(_itemRow(items[i], secondary));
    }
    return widgets;
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
                SizedBox(
                  width: 24,
                  height: 24,
                  child: AnimatedSwitcher(
                    duration: AppMotion.normal,
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      isSkipped
                          ? Icons.skip_next_rounded
                          : isDone
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      key: ValueKey(it.status),
                      color: isSkipped
                          ? AppColors.warning
                          : isDone
                          ? context.appPrimary
                          : secondary,
                    ),
                  ),
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
                if (isSkipped)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: ShapeDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      shape: AppShape.pill,
                    ),
                    child: const Text(
                      'Bỏ qua',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else if (!it.isRequired)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'Tùy chọn',
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                  ),
              ],
            ),
            if (it.note != null && it.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.sticky_note_2_outlined,
                        size: 13,
                        color: secondary,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        it.note!,
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
          ],
        ),
      ),
    );
  }
}

class _RunTimerPill extends StatelessWidget {
  final ValueListenable<Duration> elapsed;
  final bool isRunning;

  const _RunTimerPill({required this.elapsed, required this.isRunning});

  @override
  Widget build(BuildContext context) {
    final color = isRunning ? context.appPrimary : context.appTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.12),
        shape: AppShape.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: color),
          const SizedBox(width: 5),
          ValueListenableBuilder<Duration>(
            valueListenable: elapsed,
            builder: (context, duration, _) => Text(
              _formatRunDuration(duration),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRunDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours == 0) return '$mm:$ss';
  final hh = hours.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}
