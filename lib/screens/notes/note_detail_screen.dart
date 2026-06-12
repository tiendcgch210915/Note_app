import 'package:flutter/material.dart';

import '../../data/api_exception.dart';
import '../../data/notes_repository.dart';
import '../../models/note.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart';
import 'note_editor_screen.dart';

class NoteDetailScreen extends StatefulWidget {
  final String noteId;

  const NoteDetailScreen({super.key, required this.noteId});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  Note? _note;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail = await NotesRepository.instance.getDetail(widget.noteId);
      if (!mounted) return;
      setState(() => _note = detail.note);
    } on ApiException catch (e) {
      if (mounted) _showError(e.vnMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEdit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(noteId: widget.noteId),
      ),
    );
    if (mounted) _load();
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

    if (_loading && _note == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final note = _note;
    if (note == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg),
        body: const Center(child: Text('Không tìm thấy note')),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Chỉnh sửa',
            onPressed: _openEdit,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Row(
              children: [
                if (note.isPinned) ...[
                  const Icon(Icons.push_pin, size: 16),
                  const SizedBox(width: 6),
                ],
                Text(
                  AppDateUtils.formatRelative(note.updatedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              note.title,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            if (note.type == NoteType.cornell)
              _ReadOnlyCornell(note: note)
            else
              _ReadOnlyBody(text: note.body),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyBody extends StatelessWidget {
  final String? text;

  const _ReadOnlyBody({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = text?.trim();
    return Text(
      content == null || content.isEmpty ? 'Chưa có nội dung' : content,
      style: TextStyle(
        fontSize: 16,
        height: 1.55,
        color: content == null || content.isEmpty
            ? (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)
            : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
      ),
    );
  }
}

class _ReadOnlyCornell extends StatelessWidget {
  final Note note;

  const _ReadOnlyCornell({required this.note});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark ? AppColors.dividerDark : AppColors.divider;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CornellReadSection(label: 'Gợi ý', text: note.cornellCue),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Divider(height: 1, color: divider),
        ),
        _CornellReadSection(label: 'Ghi chú', text: note.body),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Divider(height: 1, color: divider),
        ),
        Text(
          'Tóm tắt',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: secondary,
          ),
        ),
        const SizedBox(height: 8),
        _ReadOnlyBody(text: note.cornellSummary),
      ],
    );
  }
}

class _CornellReadSection extends StatelessWidget {
  final String label;
  final String? text;

  const _CornellReadSection({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: secondary,
          ),
        ),
        const SizedBox(height: 8),
        _ReadOnlyBody(text: text),
      ],
    );
  }
}
