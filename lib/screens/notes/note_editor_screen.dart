import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/notes_repository.dart';
import '../../models/note.dart';
import '../../models/tag.dart';
import '../../theme/app_colors.dart';
import '../../utils/json_utils.dart';
import '../../widgets/section_header.dart';
import '../todos/todo_detail_screen.dart';

/// Editor cho note free hoặc Cornell. Nếu noteId == null → tạo mới (autosave
/// sẽ POST sau lần edit đầu tiên). Có id → fetch detail, PATCH khi edit.
///
/// 4 section dưới editor (Tags, Outgoing, Backlinks, Linked Todos) được
/// implement trong M3-4, M3-5, M3-6 — file hiện tại scaffold sẵn placeholder.
class NoteEditorScreen extends StatefulWidget {
  final String? noteId;
  const NoteEditorScreen({super.key, this.noteId});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _cornellCue = TextEditingController();
  final _cornellSummary = TextEditingController();

  NoteWithRelations? _detail;
  String? _currentNoteId;
  NoteType _type = NoteType.free;
  bool _pinned = false;
  bool _loading = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _currentNoteId = widget.noteId;
    if (_currentNoteId != null) {
      _loadDetail();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _title.dispose();
    _body.dispose();
    _cornellCue.dispose();
    _cornellSummary.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    try {
      final detail = await NotesRepository.instance.getDetail(_currentNoteId!);
      if (!mounted) return;
      _title.text = detail.note.title;
      _body.text = detail.note.body ?? '';
      _cornellCue.text = detail.note.cornellCue ?? '';
      _cornellSummary.text = detail.note.cornellSummary ?? '';
      setState(() {
        _detail = detail;
        _type = detail.note.type;
        _pinned = detail.note.isPinned;
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleAutosave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty) return;
    try {
      if (_currentNoteId == null) {
        final detail = await NotesRepository.instance.create(
          title: _title.text.trim().isEmpty ? '(Không tiêu đề)' : _title.text.trim(),
          type: _type,
          body: _body.text.isEmpty ? null : _body.text,
          cornellCue: _type == NoteType.cornell ? _cornellCue.text : null,
          cornellSummary: _type == NoteType.cornell ? _cornellSummary.text : null,
          isPinned: _pinned,
        );
        if (!mounted) return;
        setState(() {
          _currentNoteId = detail.note.id;
          _detail = detail;
        });
      } else {
        await NotesRepository.instance.update(
          _currentNoteId!,
          title: _title.text,
          type: _type,
          body: _body.text,
          cornellCue: _type == NoteType.cornell ? _cornellCue.text : null,
          cornellSummary: _type == NoteType.cornell ? _cornellSummary.text : null,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu'), duration: Duration(seconds: 1)),
        );
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _togglePin() async {
    setState(() => _pinned = !_pinned);
    if (_currentNoteId == null) return;
    try {
      await NotesRepository.instance.update(_currentNoteId!, isPinned: _pinned);
    } on ApiException catch (e) {
      setState(() => _pinned = !_pinned);
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _changeType(NoteType newType) async {
    if (newType == _type) return;
    final oldType = _type;
    setState(() => _type = newType);
    if (_currentNoteId == null) return;
    try {
      if (newType == NoteType.cornell &&
          (_cornellCue.text.trim().isEmpty || _cornellSummary.text.trim().isEmpty)) {
        _showError('Cornell cần nhập cue + summary trước');
        setState(() => _type = oldType);
        return;
      }
      await NotesRepository.instance.update(_currentNoteId!, type: newType);
    } on ApiException catch (e) {
      setState(() => _type = oldType);
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _deleteNote() async {
    if (_currentNoteId == null) {
      Navigator.of(context).pop();
      return;
    }
    try {
      await NotesRepository.instance.delete(_currentNoteId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa')),
        );
        Navigator.of(context).pop();
      }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.noteBackgroundDark : AppColors.noteBackground;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    if (_loading && _detail == null) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: _togglePin,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'free') {
                _changeType(NoteType.free);
              } else if (v == 'cornell') {
                _changeType(NoteType.cornell);
              } else if (v == 'delete') {
                _confirmDelete();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'cornell', child: Text('Đổi sang Cornell')),
              const PopupMenuItem(value: 'free', child: Text('Đổi sang Free')),
              const PopupMenuItem(value: 'delete', child: Text('Xóa', style: TextStyle(color: AppColors.danger))),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          children: [
            TextField(
              controller: _title,
              onChanged: (_) => _scheduleAutosave(),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary),
              decoration: const InputDecoration(
                hintText: 'Tiêu đề',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: _type == NoteType.cornell
                  ? _CornellLayout(
                      cueController: _cornellCue,
                      bodyController: _body,
                      summaryController: _cornellSummary,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      onChange: _scheduleAutosave,
                    )
                  : TextField(
                      controller: _body,
                      onChanged: (_) => _scheduleAutosave(),
                      maxLines: null,
                      minLines: 12,
                      style: TextStyle(fontSize: 16, color: textPrimary, height: 1.5),
                      decoration: const InputDecoration(
                        hintText: 'Bắt đầu viết...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
            ),
            // 4 section dưới editor chỉ render khi note đã được lưu lần đầu
            if (_currentNoteId != null && _detail != null) ...[
              const SizedBox(height: 16),
              _TagsSection(
                tags: _detail!.tags,
                onAdd: _addTag,
                onRemove: _removeTag,
              ),
              _OutgoingLinksSection(
                links: _detail!.outgoing,
                onAdd: _addLink,
                onRemove: _removeLink,
                onTapTarget: _openNote,
              ),
              _BacklinksSection(
                links: _detail!.incoming,
                onTapSource: _openNote,
              ),
              _LinkedTodosSection(
                todos: _detail!.todos,
                onUnlink: _unlinkTodo,
                onTap: _openTodo,
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                _ToolbarBtn(icon: Icons.format_bold),
                _ToolbarBtn(icon: Icons.format_italic),
                _ToolbarBtn(icon: Icons.format_list_bulleted),
                _ToolbarBtn(icon: Icons.image_outlined),
                _ToolbarBtn(icon: Icons.link),
                _ToolbarBtn(icon: Icons.local_offer_outlined),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa note?'),
        content: const Text('Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteNote();
            },
            child: const Text('Xóa', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  // ─── Tags section helpers ─────────────────────────────────────
  Future<void> _addTag() async {
    if (_currentNoteId == null) {
      _showError('Lưu note trước khi thêm tag');
      return;
    }
    final result = await showDialog<({String name, String color})>(
      context: context,
      builder: (_) => const _TagDialog(),
    );
    if (result == null || !mounted) return;
    try {
      final tag = await NotesRepository.instance.attachTag(
        _currentNoteId!,
        name: result.name,
        color: result.color,
      );
      setState(() {
        _detail = NoteWithRelations(
          note: _detail!.note,
          tags: [..._detail!.tags, tag],
          outgoing: _detail!.outgoing,
          incoming: _detail!.incoming,
          todos: _detail!.todos,
        );
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _removeTag(Tag tag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bỏ tag?'),
        content: Text('Bỏ tag "${tag.name}" khỏi note này?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Bỏ', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true || _currentNoteId == null) return;
    try {
      await NotesRepository.instance.detachTag(_currentNoteId!, tag.id);
      setState(() {
        _detail = NoteWithRelations(
          note: _detail!.note,
          tags: _detail!.tags.where((t) => t.id != tag.id).toList(),
          outgoing: _detail!.outgoing,
          incoming: _detail!.incoming,
          todos: _detail!.todos,
        );
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  // ─── Outgoing Links helpers ───────────────────────────────────
  Future<void> _addLink() async {
    if (_currentNoteId == null) {
      _showError('Lưu note trước khi thêm liên kết');
      return;
    }
    final picked = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NotePicker(excludeId: _currentNoteId!),
    );
    if (picked == null || !mounted) return;
    final label = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Nhãn liên kết'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'Tùy chọn, vd "tham khảo"'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Bỏ qua')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Thêm')),
          ],
        );
      },
    );
    try {
      await NotesRepository.instance.addLink(
        _currentNoteId!,
        picked.id,
        label: label == null || label.isEmpty ? null : label,
      );
      await _loadDetail(); // re-fetch để có target_title
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  Future<void> _removeLink(OutgoingLink link) async {
    if (_currentNoteId == null) return;
    try {
      await NotesRepository.instance.removeLink(_currentNoteId!, link.targetNoteId);
      setState(() {
        _detail = NoteWithRelations(
          note: _detail!.note,
          tags: _detail!.tags,
          outgoing: _detail!.outgoing.where((l) => l.id != link.id).toList(),
          incoming: _detail!.incoming,
          todos: _detail!.todos,
        );
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }

  // ─── Navigation helpers ───────────────────────────────────────
  Future<void> _openNote(String noteId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: noteId)),
    );
    if (mounted) _loadDetail(); // refresh khi quay về
  }

  Future<void> _openTodo(String todoId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: todoId)),
    );
    if (mounted) _loadDetail();
  }

  Future<void> _unlinkTodo(LinkedTodo todo) async {
    if (_currentNoteId == null) return;
    try {
      await NotesRepository.instance.unlinkTodo(_currentNoteId!, todo.id);
      setState(() {
        _detail = NoteWithRelations(
          note: _detail!.note,
          tags: _detail!.tags,
          outgoing: _detail!.outgoing,
          incoming: _detail!.incoming,
          todos: _detail!.todos.where((t) => t.id != todo.id).toList(),
        );
      });
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    }
  }
}

// ─── Section widgets ─────────────────────────────────────────────

class _TagsSection extends StatelessWidget {
  final List<Tag> tags;
  final VoidCallback onAdd;
  final void Function(Tag) onRemove;
  const _TagsSection({required this.tags, required this.onAdd, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(label: 'Tags', padding: EdgeInsets.only(top: 8, bottom: 8)),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ...tags.map((t) => GestureDetector(
                  onLongPress: () => onRemove(t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: t.color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      t.name,
                      style: TextStyle(fontSize: 12, color: t.color, fontWeight: FontWeight.w600),
                    ),
                  ),
                )),
            ActionChip(
              avatar: const Icon(Icons.add, size: 14),
              label: const Text('Tag', style: TextStyle(fontSize: 12)),
              onPressed: onAdd,
            ),
          ],
        ),
        if (tags.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Chưa có tag · long-press chip để bỏ',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ),
      ],
    );
  }
}

class _OutgoingLinksSection extends StatelessWidget {
  final List<OutgoingLink> links;
  final VoidCallback onAdd;
  final void Function(OutgoingLink) onRemove;
  final void Function(String) onTapTarget;
  const _OutgoingLinksSection({
    required this.links,
    required this.onAdd,
    required this.onRemove,
    required this.onTapTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          label: 'Liên kết',
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          trailing: TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Thêm', style: TextStyle(fontSize: 12)),
            onPressed: onAdd,
          ),
        ),
        if (links.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('(Chưa có liên kết)',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          )
        else
          ...links.map((l) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.arrow_outward, size: 18, color: AppColors.primary),
                title: Text(
                  l.targetTitle.isEmpty ? '(Note đã đổi tên)' : l.targetTitle,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: l.label == null ? null : Text(l.label!, style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onRemove(l),
                ),
                onTap: () => onTapTarget(l.targetNoteId),
              )),
      ],
    );
  }
}

class _BacklinksSection extends StatelessWidget {
  final List<IncomingLink> links;
  final void Function(String) onTapSource;
  const _BacklinksSection({required this.links, required this.onTapSource});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          label: 'Backlinks',
          padding: EdgeInsets.only(top: 16, bottom: 4),
        ),
        if (links.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('(Chưa có note nào liên kết tới đây)',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          )
        else
          ...links.map((l) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.subdirectory_arrow_left, size: 18, color: AppColors.primary),
                title: Text(
                  l.sourceTitle.isEmpty ? '(Note đã đổi tên)' : l.sourceTitle,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: l.label == null ? null : Text(l.label!, style: const TextStyle(fontSize: 11)),
                onTap: () => onTapSource(l.sourceNoteId),
              )),
      ],
    );
  }
}

class _LinkedTodosSection extends StatelessWidget {
  final List<LinkedTodo> todos;
  final void Function(LinkedTodo) onUnlink;
  final void Function(String) onTap;
  const _LinkedTodosSection({
    required this.todos,
    required this.onUnlink,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          label: 'Todos liên quan',
          padding: EdgeInsets.only(top: 16, bottom: 4),
        ),
        if (todos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('(Chưa có todo liên kết)',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          )
        else
          ...todos.map((t) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  t.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: t.isDone ? AppColors.primary : AppColors.textSecondary,
                ),
                title: Text(
                  t.title,
                  style: TextStyle(
                    fontSize: 14,
                    decoration: t.isDone ? TextDecoration.lineThrough : null,
                    color: t.isDone ? AppColors.textSecondary : null,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.link_off, size: 18),
                  onPressed: () => onUnlink(t),
                ),
                onTap: () => onTap(t.id),
              )),
      ],
    );
  }
}

// ─── Tag dialog ─────────────────────────────────────────────────

class _TagDialog extends StatefulWidget {
  const _TagDialog();

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  final _ctrl = TextEditingController();
  Color _color = AppColors.tagIndigo;

  static const _colorPool = [
    AppColors.tagIndigo,
    AppColors.tagGreen,
    AppColors.tagAmber,
    AppColors.tagRed,
    AppColors.tagPink,
    AppColors.tagCyan,
    AppColors.tagPurple,
    AppColors.tagSlate,
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Tên tag (1-64 ký tự)'),
          ),
          const SizedBox(height: 16),
          const Text('Màu', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: _colorPool.map((c) {
              return GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: c == _color ? Border.all(color: AppColors.primary, width: 2.5) : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Hủy')),
        TextButton(
          onPressed: () {
            final name = _ctrl.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop((name: name, color: formatColorHex(_color)));
          },
          child: const Text('Thêm'),
        ),
      ],
    );
  }
}

// ─── Note picker BottomSheet (cho Outgoing Links) ───────────────

class _NotePicker extends StatefulWidget {
  final String excludeId;
  const _NotePicker({required this.excludeId});

  @override
  State<_NotePicker> createState() => _NotePickerState();
}

class _NotePickerState extends State<_NotePicker> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Note> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final resp = await NotesRepository.instance.list(
        q: _ctrl.text.trim().isEmpty ? null : _ctrl.text.trim(),
        limit: 20,
      );
      setState(() {
        _results = resp.items.where((n) => n.id != widget.excludeId).toList();
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _fetch);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _ctrl,
                onChanged: _onChanged,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Tìm note để liên kết',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
            ),
            Expanded(
              child: _loading && _results.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _results.length,
                      itemBuilder: (ctx, i) {
                        final n = _results[i];
                        return ListTile(
                          leading: const Icon(Icons.sticky_note_2_outlined),
                          title: Text(n.title),
                          subtitle: Text(n.previewBody, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(context).pop(n),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CornellLayout extends StatelessWidget {
  final TextEditingController cueController;
  final TextEditingController bodyController;
  final TextEditingController summaryController;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onChange;

  const _CornellLayout({
    required this.cueController,
    required this.bodyController,
    required this.summaryController,
    required this.textPrimary,
    required this.textSecondary,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark ? AppColors.dividerDark : AppColors.divider;
    return Column(
      children: [
        Expanded(
          flex: 7,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: divider)),
                  ),
                  child: TextField(
                    controller: cueController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) => onChange(),
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: textPrimary,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Gợi ý',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.only(top: 4, left: 4),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextField(
                    controller: bodyController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) => onChange(),
                    style: TextStyle(fontSize: 15, color: textPrimary, height: 1.4),
                    decoration: const InputDecoration(
                      hintText: 'Ghi chú',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.only(top: 4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 1,
          color: divider,
          margin: const EdgeInsets.symmetric(vertical: 8),
        ),
        Expanded(
          flex: 3,
          child: TextField(
            controller: summaryController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            onChanged: (_) => onChange(),
            style: TextStyle(fontSize: 14, color: textPrimary, height: 1.4),
            decoration: const InputDecoration(
              hintText: 'Tóm tắt',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  const _ToolbarBtn({required this.icon});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: () {},
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }
}
