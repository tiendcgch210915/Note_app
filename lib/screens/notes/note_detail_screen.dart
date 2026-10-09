import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../data/api_exception.dart';
import '../../data/notes_repository.dart';
import '../../models/note.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_snack.dart';
import '../../utils/date_utils.dart';
import '../../utils/note_delta_utils.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/cornell_note_layout.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/note_quill_editor.dart';
import 'note_editor_screen.dart';

class NoteDetailScreen extends StatefulWidget {
  const NoteDetailScreen({super.key, required this.noteId, this.repository});

  final String noteId;
  final NotesRepository? repository;

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  final _bodyFocus = FocusNode();
  final _cueFocus = FocusNode();
  final _summaryFocus = FocusNode();
  late final QuillController _body;
  late final QuillController _cue;
  late final QuillController _summary;

  final _scroll = ScrollController();
  bool _showBarTitle = false;
  String? _loadError;

  NoteWithRelations? _detail;
  bool _loading = false;
  bool _hydrating = false;
  bool _dirty = false;
  bool _saving = false;
  bool _saveQueued = false;
  bool _canPop = false;
  int _revision = 0;
  String _contentSignature = '';
  Timer? _saveTimer;

  NotesRepository get _repository =>
      widget.repository ?? NotesRepository.instance;

  @override
  void initState() {
    super.initState();
    _body = createNoteQuillController();
    _cue = createNoteQuillController();
    _summary = createNoteQuillController();
    _contentSignature = _currentContentSignature();
    for (final controller in [_body, _cue, _summary]) {
      controller.addListener(_handleDocumentChanged);
    }
    for (final focus in [_bodyFocus, _cueFocus, _summaryFocus]) {
      focus.addListener(_handleFocusChanged);
    }
    _scroll.addListener(_handleScroll);
    _load();
  }

  /// Tiêu đề trên thanh AppBar chỉ hiện khi tiêu đề lớn đã cuộn khỏi màn hình.
  void _handleScroll() {
    final show = _scroll.hasClients && _scroll.offset > 56;
    if (show != _showBarTitle && mounted) setState(() => _showBarTitle = show);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_handleScroll)
      ..dispose();
    _saveTimer?.cancel();
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

  Future<void> _load() async {
    setState(() {
      _loading = _detail == null;
      _loadError = null;
    });
    try {
      final detail = await _repository.getDetail(widget.noteId);
      if (!mounted) return;
      _applyDetail(detail);
      unawaited(_refreshInBackground());
    } on ApiException catch (error) {
      if (!mounted) return;
      if (_detail == null) {
        setState(() => _loadError = error.vnMessage);
      } else {
        _showError(error.vnMessage);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshInBackground() async {
    if (_dirty || _saving) return;
    try {
      final detail = await _repository.refreshDetail(widget.noteId);
      if (!mounted || _dirty || _saving || _activeController != null) return;
      _applyDetail(detail);
    } on ApiException {
      // Cached detail remains available while offline.
    }
  }

  Future<void> _refreshFromPull() async {
    if (!await _flushSave() || !mounted) return;
    try {
      final detail = await _repository.refreshDetail(widget.noteId);
      if (mounted) _applyDetail(detail);
    } on ApiException catch (error) {
      if (mounted) _showError(error.vnMessage);
    }
  }

  void _applyDetail(NoteWithRelations detail) {
    _hydrating = true;
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
      _dirty = false;
    });
    _hydrating = false;
  }

  void _handleDocumentChanged() {
    if (_hydrating) return;
    final signature = _currentContentSignature();
    if (signature == _contentSignature) return;
    _contentSignature = signature;
    _revision++;
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), _save);
    if (mounted) setState(() {});
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _save() async {
    _saveTimer?.cancel();
    final detail = _detail;
    if (!_dirty || detail == null) return true;
    if (_saving) {
      _saveQueued = true;
      return true;
    }

    final note = detail.note;
    final bodyPlain = notePlainTextFromDocument(_body.document);
    final cuePlain = notePlainTextFromDocument(_cue.document);
    final summaryPlain = notePlainTextFromDocument(_summary.document);
    final saveRevision = _revision;

    _saving = true;
    if (mounted) setState(() {});

    try {
      await _repository.update(
        note.id,
        body: bodyPlain,
        clearBody: bodyPlain.isEmpty,
        bodyDelta: noteDeltaFromDocument(_body.document),
        cornellCue: note.type == NoteType.cornell ? cuePlain : null,
        clearCornellCue: note.type == NoteType.cornell && cuePlain.isEmpty,
        cornellCueDelta: note.type == NoteType.cornell && cuePlain.isNotEmpty
            ? noteDeltaFromDocument(_cue.document)
            : null,
        clearCornellCueDelta: note.type == NoteType.cornell && cuePlain.isEmpty,
        cornellSummary: note.type == NoteType.cornell ? summaryPlain : null,
        clearCornellSummary:
            note.type == NoteType.cornell && summaryPlain.isEmpty,
        cornellSummaryDelta:
            note.type == NoteType.cornell && summaryPlain.isNotEmpty
            ? noteDeltaFromDocument(_summary.document)
            : null,
        clearCornellSummaryDelta:
            note.type == NoteType.cornell && summaryPlain.isEmpty,
        contentFormat: noteContentFormatQuill,
      );
      final local = await _repository.getLocalDetail(note.id);
      if (local != null) _detail = local;
      if (saveRevision == _revision) {
        _dirty = false;
        _contentSignature = _currentContentSignature();
      }
      if (mounted) setState(() {});
      return true;
    } on ApiException catch (error) {
      _dirty = true;
      if (mounted) _showError(error.vnMessage);
      return false;
    } catch (error) {
      _dirty = true;
      if (mounted) _showError('Không thể lưu note: $error');
      return false;
    } finally {
      _saving = false;
      if (_saveQueued || (_dirty && saveRevision != _revision)) {
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

  Future<void> _openEditor() async {
    if (!await _flushSave() || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          noteId: widget.noteId,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted) await _load();
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

  String _currentContentSignature() => jsonEncode([
    _body.document.toDelta().toJson(),
    _cue.document.toDelta().toJson(),
    _summary.document.toDelta().toJson(),
  ]);

  void _showError(String message) {
    showAppSnack(context, message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final background = context.appNoteBackground;
    final detail = _detail;
    final activeController = _activeController;
    final bottomPadding = noteKeyboardAwareBottomPadding(
      viewportSize: MediaQuery.sizeOf(context),
      keyboardInset: MediaQuery.viewInsetsOf(context).bottom,
      editorFocused: activeController != null,
      restingPadding: activeController == null ? 48 : 112,
    );

    if (_loading && detail == null) {
      return Scaffold(
        backgroundColor: background,
        appBar: AppBar(backgroundColor: background),
        body: const AppSpinner(),
      );
    }
    if (detail == null) {
      return Scaffold(
        backgroundColor: background,
        appBar: AppBar(backgroundColor: background),
        body: _loadError != null
            ? AppErrorState(message: _loadError!, onRetry: _load)
            : const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Không tìm thấy note',
              ),
      );
    }

    final note = detail.note;
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
          title: AnimatedOpacity(
            opacity: _showBarTitle ? 1 : 0,
            duration: AppMotion.normal,
            child: Text(
              note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          actions: [
            // Ô cố định chỗ cho spinner để thanh công cụ không bị nhảy bố cục.
            SizedBox(
              width: 36,
              child: _saving
                  ? const AppSpinner(radius: 8, centered: false)
                  : null,
            ),
            if (activeController != null)
              NoteQuillAppBarActions(
                controller: activeController,
                focusNode: _activeFocusNode,
              ),
            IconButton(
              tooltip: 'Chỉnh sửa thông tin',
              onPressed: _openEditor,
              icon: const Icon(Icons.edit_rounded),
            ),
          ],
        ),
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _refreshFromPull,
              child: ListView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPadding),
                children: [
                  Row(
                    children: [
                      if (note.isPinned) ...[
                        Icon(
                          Icons.push_pin_rounded,
                          size: 16,
                          color: context.appTextSecondary,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        AppDateUtils.formatRelative(note.updatedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appTextSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (note.type == NoteType.cornell)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: ShapeDecoration(
                            color: context.appPrimarySoft,
                            shape: AppShape.pill,
                          ),
                          child: Text(
                            'Cornell',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.appPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    note.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (note.type == NoteType.free)
                    NoteQuillEditor(
                      controller: _body,
                      focusNode: _bodyFocus,
                      placeholder: 'Không có nội dung',
                      minHeight: 360,
                    )
                  else
                    CornellNoteLayout(
                      notes: NoteQuillEditor(
                        controller: _body,
                        focusNode: _bodyFocus,
                        placeholder: 'Không có nội dung',
                        minHeight: 240,
                      ),
                      cues: NoteQuillEditor(
                        controller: _cue,
                        focusNode: _cueFocus,
                        placeholder: 'Chưa có Cues',
                        minHeight: 160,
                      ),
                      summary: NoteQuillEditor(
                        controller: _summary,
                        focusNode: _summaryFocus,
                        placeholder: 'Chưa có Summary',
                        minHeight: 140,
                      ),
                    ),
                ],
              ),
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
