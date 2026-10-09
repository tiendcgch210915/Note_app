import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../data/api_exception.dart';
import '../../data/notes_repository.dart';
import '../../models/note.dart';
import '../../models/tag.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_snack.dart';
import '../../utils/note_delta_utils.dart';
import '../../widgets/app_segmented_control.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/cornell_note_layout.dart';
import '../../widgets/note_quill_editor.dart';
import '../../widgets/note_relation_pickers.dart';
import '../../widgets/note_relations_section.dart';
import '../../widgets/note_text_editing_controller.dart';
import '../todos/todo_detail_screen.dart';

enum _EditorSaveState { saved, saving, pending, error }

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.initialType,
    this.repository,
  });

  final String? noteId;
  final NoteType? initialType;
  final NotesRepository? repository;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _title = NoteTextEditingController();
  final _bodyFocus = FocusNode();
  final _cueFocus = FocusNode();
  final _summaryFocus = FocusNode();

  late final QuillController _body;
  late final QuillController _cue;
  late final QuillController _summary;

  NoteWithRelations? _detail;
  String? _noteId;
  NoteType _type = NoteType.free;
  bool _pinned = false;
  bool _loading = false;
  bool _hydrating = false;
  bool _dirty = false;
  bool _saving = false;
  bool _saveQueued = false;
  bool _canPop = false;
  int _revision = 0;
  Timer? _saveTimer;
  _EditorSaveState _saveState = _EditorSaveState.saved;
  String _contentSignature = '';

  NotesRepository get _repository =>
      widget.repository ?? NotesRepository.instance;

  @override
  void initState() {
    super.initState();
    _noteId = widget.noteId;
    _type = widget.initialType ?? NoteType.free;
    _body = createNoteQuillController();
    _cue = createNoteQuillController();
    _summary = createNoteQuillController();
    _contentSignature = _currentContentSignature();
    _title.addListener(_markChanged);
    for (final controller in [_body, _cue, _summary]) {
      controller.addListener(_handleDocumentChanged);
    }
    for (final focus in [_bodyFocus, _cueFocus, _summaryFocus]) {
      focus.addListener(_handleFocusChanged);
    }
    if (_noteId != null) {
      _load();
    } else {
      _requestDefaultFocus();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _title
      ..removeListener(_markChanged)
      ..dispose();
    for (final controller in [_body, _cue, _summary]) {
      controller
        ..removeListener(_handleDocumentChanged)
        ..dispose();
    }
    for (final focus in [_bodyFocus, _cueFocus, _summaryFocus]) {
      focus
        ..removeListener(_handleFocusChanged)
        ..dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool refreshRemote = false}) async {
    if (_noteId == null) return;
    setState(() => _loading = _detail == null);
    try {
      final detail = refreshRemote
          ? await _repository.refreshDetail(_noteId!)
          : await _repository.getDetail(_noteId!);
      if (!mounted) return;
      _applyDetail(detail);
      if (!refreshRemote) {
        unawaited(_refreshInBackground());
      }
    } on ApiException catch (error) {
      if (mounted) _showError(error.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      final detail = await _repository.refreshDetail(_noteId!);
      if (!mounted || _dirty || _saving) return;
      _applyDetail(detail);
    } on ApiException {
      // Local detail remains usable while offline.
    }
  }

  void _applyDetail(NoteWithRelations detail) {
    _hydrating = true;
    _title.text = detail.note.title;
    _body.document = noteDocumentFrom(
      delta: detail.note.bodyDelta,
      plainText: detail.note.body,
    );
    _cue.document = noteDocumentFrom(
      delta: detail.note.cornellCueDelta,
      plainText: detail.note.cornellCue,
    );
    _summary.document = noteDocumentFrom(
      delta: detail.note.cornellSummaryDelta,
      plainText: detail.note.cornellSummary,
    );
    _contentSignature = _currentContentSignature();
    setState(() {
      _detail = detail;
      _type = detail.note.type;
      _pinned = detail.note.isPinned;
      _dirty = false;
      _saveState = _EditorSaveState.saved;
    });
    _hydrating = false;
  }

  void _handleDocumentChanged() {
    if (_hydrating) return;
    final signature = _currentContentSignature();
    if (signature == _contentSignature) return;
    _contentSignature = signature;
    _markChanged();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _markChanged() {
    if (_hydrating) return;
    _revision++;
    _dirty = true;
    _saveState = _EditorSaveState.pending;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
    if (mounted) setState(() {});
  }

  Future<bool> _save() async {
    _saveTimer?.cancel();
    if (!_dirty) return true;
    if (_saving) {
      _saveQueued = true;
      return true;
    }

    final bodyPlain = notePlainTextFromDocument(_body.document);
    final cuePlain = notePlainTextFromDocument(_cue.document);
    final summaryPlain = notePlainTextFromDocument(_summary.document);
    final hasContent =
        _title.text.trim().isNotEmpty ||
        bodyPlain.trim().isNotEmpty ||
        (_type == NoteType.cornell &&
            (cuePlain.trim().isNotEmpty || summaryPlain.trim().isNotEmpty));
    if (_noteId == null && !hasContent) {
      _dirty = false;
      _saveState = _EditorSaveState.saved;
      if (mounted) setState(() {});
      return true;
    }

    final saveRevision = _revision;
    _saving = true;
    _saveState = _EditorSaveState.saving;
    if (mounted) setState(() {});

    try {
      final bodyDelta = noteDeltaFromDocument(_body.document);
      final cueDelta = noteDeltaFromDocument(_cue.document);
      final summaryDelta = noteDeltaFromDocument(_summary.document);
      if (_noteId == null) {
        final detail = await _repository.create(
          title: _title.text,
          type: _type,
          body: bodyPlain,
          bodyDelta: bodyDelta,
          cornellCue: _type == NoteType.cornell ? cuePlain : null,
          cornellCueDelta: _type == NoteType.cornell && cuePlain.isNotEmpty
              ? cueDelta
              : null,
          cornellSummary: _type == NoteType.cornell ? summaryPlain : null,
          cornellSummaryDelta:
              _type == NoteType.cornell && summaryPlain.isNotEmpty
              ? summaryDelta
              : null,
          isPinned: _pinned,
        );
        _noteId = detail.note.id;
        _detail = detail;
      } else {
        await _repository.update(
          _noteId!,
          title: _title.text,
          type: _type,
          body: bodyPlain,
          clearBody: bodyPlain.isEmpty,
          bodyDelta: bodyDelta,
          cornellCue: _type == NoteType.cornell ? cuePlain : null,
          clearCornellCue: _type == NoteType.cornell && cuePlain.isEmpty,
          cornellCueDelta: _type == NoteType.cornell && cuePlain.isNotEmpty
              ? cueDelta
              : null,
          clearCornellCueDelta: _type != NoteType.cornell || cuePlain.isEmpty,
          cornellSummary: _type == NoteType.cornell ? summaryPlain : null,
          clearCornellSummary:
              _type == NoteType.cornell && summaryPlain.isEmpty,
          cornellSummaryDelta:
              _type == NoteType.cornell && summaryPlain.isNotEmpty
              ? summaryDelta
              : null,
          clearCornellSummaryDelta:
              _type != NoteType.cornell || summaryPlain.isEmpty,
          contentFormat: noteContentFormatQuill,
          isPinned: _pinned,
        );
        _detail = await _repository.getLocalDetail(_noteId!);
      }
      if (saveRevision == _revision) {
        _dirty = false;
        _saveState = _EditorSaveState.pending;
      }
      if (mounted) setState(() {});
      return true;
    } on ApiException catch (error) {
      _dirty = true;
      _saveState = _EditorSaveState.error;
      if (mounted) _showError(error.vnMessage);
      return false;
    } catch (error) {
      _dirty = true;
      _saveState = _EditorSaveState.error;
      if (mounted) _showError('Không thể lưu note: $error');
      return false;
    } finally {
      _saving = false;
      if (_saveQueued || _dirty && saveRevision != _revision) {
        _saveQueued = false;
        _saveTimer = Timer(const Duration(milliseconds: 150), _save);
      }
      if (mounted) setState(() {});
    }
  }

  Future<bool> _flushSave() async {
    _saveTimer?.cancel();
    while (_saving) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return _dirty ? _save() : true;
  }

  Future<void> _handleBack(Object? result) async {
    if (!await _flushSave() || !mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> _changeType(NoteType nextType) async {
    if (nextType == _type) return;
    if (!await _flushSave() || !mounted) return;
    if (_type == NoteType.cornell && nextType == NoteType.free) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chuyển sang ghi chú thường?'),
          content: const Text(
            'Chuyển sang ghi chú thường sẽ xóa cột gợi ý và phần tóm tắt.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Chuyển'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (_type == NoteType.cornell && nextType == NoteType.free) {
      _hydrating = true;
      _cue.document = noteDocumentFrom();
      _summary.document = noteDocumentFrom();
      _contentSignature = _currentContentSignature();
      _hydrating = false;
    }
    setState(() => _type = nextType);
    _markChanged();
    await _save();
    _requestDefaultFocus();
  }

  Future<void> _togglePin() async {
    setState(() => _pinned = !_pinned);
    _markChanged();
    await _save();
  }

  Future<void> _delete() async {
    if (!await _flushSave() || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa note?'),
        content: const Text('Note sẽ được xóa trên thiết bị và đồng bộ sau.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_noteId != null) await _repository.delete(_noteId!);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _editTags() async {
    if (!await _ensureSavedForRelations() || !mounted) return;
    final current = _detail?.tags ?? const <Tag>[];
    final selected = await showNoteTagSelector(context, selected: current);
    if (selected == null || !mounted) return;
    final oldIds = current.map((tag) => tag.id).toSet();
    final newIds = selected.map((tag) => tag.id).toSet();
    for (final tag in selected.where((tag) => !oldIds.contains(tag.id))) {
      await _repository.attachTag(_noteId!, tagId: tag.id);
    }
    for (final tag in current.where((tag) => !newIds.contains(tag.id))) {
      await _repository.detachTag(_noteId!, tag.id);
    }
    await _reloadLocalDetail();
  }

  Future<void> _addLink() async {
    if (!await _ensureSavedForRelations() || !mounted) return;
    final picked = await showNotePicker(
      context,
      excludeId: _noteId!,
      excludedIds:
          _detail?.outgoing.map((link) => link.targetNoteId).toSet() ?? {},
    );
    if (picked == null || !mounted) return;
    final label = await _askLinkLabel();
    if (!mounted) return;
    await _repository.addLink(_noteId!, picked.id, label: label);
    await _reloadLocalDetail();
  }

  Future<String?> _askLinkLabel() {
    return showAppTextInputDialog(
      context,
      title: 'Nhãn liên kết',
      hintText: 'Tùy chọn',
      confirmLabel: 'Thêm',
      cancelLabel: 'Bỏ qua',
      maxLength: 100,
    );
  }

  Future<void> _removeLink(OutgoingLink link) async {
    await _repository.removeLink(_noteId!, link.targetNoteId);
    await _reloadLocalDetail();
  }

  Future<void> _addTodo() async {
    if (!await _ensureSavedForRelations() || !mounted) return;
    final todo = await showNoteTodoPicker(
      context,
      excludedIds: _detail?.todos.map((todo) => todo.id).toSet() ?? {},
    );
    if (todo == null) return;
    await _repository.linkTodo(_noteId!, todo.id);
    await _reloadLocalDetail();
  }

  Future<void> _removeTodo(LinkedTodo todo) async {
    await _repository.unlinkTodo(_noteId!, todo.id);
    await _reloadLocalDetail();
  }

  Future<bool> _ensureSavedForRelations() async {
    if (!await _flushSave()) return false;
    if (_noteId != null) return true;
    _showError('Hãy nhập tiêu đề hoặc nội dung trước');
    return false;
  }

  Future<void> _reloadLocalDetail() async {
    if (_noteId == null) return;
    final detail = await _repository.getLocalDetail(_noteId!);
    if (detail != null && mounted) setState(() => _detail = detail);
  }

  Future<void> _openNote(String id) async {
    if (!await _flushSave() || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            NoteEditorScreen(noteId: id, repository: widget.repository),
      ),
    );
    await _reloadLocalDetail();
  }

  Future<void> _openTodo(String id) async {
    if (!await _flushSave() || !mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: id)));
    await _reloadLocalDetail();
  }

  QuillController? get _activeController {
    if (_bodyFocus.hasFocus) return _body;
    if (_cueFocus.hasFocus) return _cue;
    if (_summaryFocus.hasFocus) return _summary;
    return null;
  }

  FocusNode? get _activeFocusNode {
    if (_bodyFocus.hasFocus) return _bodyFocus;
    if (_cueFocus.hasFocus) return _cueFocus;
    if (_summaryFocus.hasFocus) return _summaryFocus;
    return null;
  }

  void _requestDefaultFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bodyFocus.requestFocus();
    });
  }

  String _currentContentSignature() => jsonEncode([
    _body.document.toDelta().toJson(),
    _cue.document.toDelta().toJson(),
    _summary.document.toDelta().toJson(),
  ]);

  String get _saveLabel => switch (_saveState) {
    _EditorSaveState.saved => 'Đã lưu',
    _EditorSaveState.saving => 'Đang lưu',
    _EditorSaveState.pending => 'Chờ đồng bộ',
    _EditorSaveState.error => 'Lỗi đồng bộ',
  };

  IconData get _saveIcon => switch (_saveState) {
    _EditorSaveState.saved => Icons.check_circle_outline_rounded,
    _EditorSaveState.saving => Icons.sync_rounded,
    _EditorSaveState.pending => Icons.cloud_upload_outlined,
    _EditorSaveState.error => Icons.error_outline_rounded,
  };

  void _showError(String message) {
    showAppSnack(context, message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final background = context.appNoteBackground;
    final activeController = _activeController;
    final bottomPadding = noteKeyboardAwareBottomPadding(
      viewportSize: MediaQuery.sizeOf(context),
      keyboardInset: MediaQuery.viewInsetsOf(context).bottom,
      editorFocused: activeController != null,
      restingPadding: activeController == null ? 80 : 112,
    );

    if (_loading && _detail == null) {
      return Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          leading: IconButton(
            tooltip: 'Quay lại',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
        ),
        body: const AppSpinner(),
      );
    }

    return PopScope<Object?>(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleBack(result));
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          leading: IconButton(
            tooltip: 'Quay lại',
            onPressed: () => _handleBack(null),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          title: AnimatedSwitcher(
            duration: AppMotion.normal,
            child: Row(
              key: ValueKey(_saveState),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _saveIcon,
                  size: 16,
                  color: _saveState == _EditorSaveState.error
                      ? AppColors.danger
                      : context.appTextSecondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _saveLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _saveState == _EditorSaveState.error
                          ? AppColors.danger
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (activeController != null)
              NoteQuillAppBarActions(
                controller: activeController,
                focusNode: _activeFocusNode,
              ),
            IconButton(
              tooltip: _pinned ? 'Bỏ ghim' : 'Ghim note',
              onPressed: () {
                AppHaptics.selection();
                _togglePin();
              },
              icon: AnimatedSwitcher(
                duration: AppMotion.fast,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  _pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  key: ValueKey(_pinned),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Xóa note',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        body: Stack(
          children: [
            ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPadding),
              children: [
                TextField(
                  controller: _title,
                  maxLength: 500,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Tiêu đề',
                    counterText: '',
                    border: InputBorder.none,
                    filled: false,
                  ),
                ),
                const SizedBox(height: 8),
                AppSegmentedControl<NoteType>(
                  segments: const [
                    AppSegment(
                      value: NoteType.free,
                      icon: Icons.notes_rounded,
                      label: 'Ghi chú thường',
                    ),
                    AppSegment(
                      value: NoteType.cornell,
                      icon: Icons.view_column_rounded,
                      label: 'Cornell',
                    ),
                  ],
                  value: _type,
                  onChanged: _changeType,
                ),
                const SizedBox(height: 20),
                if (_type == NoteType.free)
                  NoteQuillEditor(
                    controller: _body,
                    focusNode: _bodyFocus,
                    placeholder: 'Ghi nội dung chính...',
                    autoFocus: widget.noteId == null,
                    minHeight: 420,
                  )
                else
                  CornellNoteLayout(
                    notes: NoteQuillEditor(
                      controller: _body,
                      focusNode: _bodyFocus,
                      placeholder: 'Ghi nội dung chính...',
                      autoFocus: widget.noteId == null,
                      minHeight: 260,
                    ),
                    cues: NoteQuillEditor(
                      controller: _cue,
                      focusNode: _cueFocus,
                      placeholder: 'Từ khóa hoặc câu hỏi gợi nhớ...',
                      minHeight: 180,
                    ),
                    summary: NoteQuillEditor(
                      controller: _summary,
                      focusNode: _summaryFocus,
                      placeholder: 'Tóm tắt nội dung cốt lõi...',
                      minHeight: 140,
                    ),
                  ),
                if (_noteId != null && _detail != null)
                  NoteRelationsSection(
                    tags: _detail!.tags,
                    outgoing: _detail!.outgoing,
                    incoming: _detail!.incoming,
                    todos: _detail!.todos,
                    onEditTags: _editTags,
                    onAddLink: _addLink,
                    onRemoveLink: _removeLink,
                    onOpenNote: _openNote,
                    onAddTodo: _addTodo,
                    onRemoveTodo: _removeTodo,
                    onOpenTodo: _openTodo,
                  ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSwitcher(
                duration: AppMotion.normal,
                switchInCurve: AppMotion.curve,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.passthrough,
                  alignment: Alignment.bottomCenter,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.6),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: activeController != null
                    ? NoteQuillToolbar(
                        key: const ValueKey('note-toolbar'),
                        controller: activeController,
                      )
                    : const SizedBox.shrink(key: ValueKey('note-no-toolbar')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
