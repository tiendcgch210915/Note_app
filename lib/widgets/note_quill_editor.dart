import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../utils/note_delta_utils.dart';

QuillController createNoteQuillController({
  Map<String, dynamic>? delta,
  String? plainText,
  bool readOnly = false,
}) {
  return QuillController(
    document: noteDocumentFrom(delta: delta, plainText: plainText),
    selection: const TextSelection.collapsed(offset: 0),
    readOnly: readOnly,
  );
}

double noteKeyboardAwareBottomPadding({
  required Size viewportSize,
  required double keyboardInset,
  required bool editorFocused,
  required double restingPadding,
}) {
  if (!editorFocused) return restingPadding;

  const focusedPaddingWithoutKeyboard = 160.0;
  if (keyboardInset <= 0) {
    return math.max(restingPadding, focusedPaddingWithoutKeyboard);
  }

  const toolbarAndBreathingRoom = 112.0;
  final viewportLift = viewportSize.height * 0.44;
  final keyboardLift = keyboardInset + toolbarAndBreathingRoom;
  return math.max(restingPadding, math.max(viewportLift, keyboardLift));
}

@visibleForTesting
double noteScrollOffsetForCaret({
  required double currentOffset,
  required double minOffset,
  required double maxOffset,
  required double caretTop,
  required double caretBottom,
  required double visibleTop,
  required double visibleBottom,
}) {
  const margin = 18.0;
  var target = currentOffset;
  if (caretBottom + margin > visibleBottom) {
    target += caretBottom + margin - visibleBottom;
  } else if (caretTop - margin < visibleTop) {
    target -= visibleTop - caretTop + margin;
  }
  return target.clamp(minOffset, maxOffset).toDouble();
}

class NoteQuillEditor extends StatefulWidget {
  const NoteQuillEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    this.readOnly = false,
    this.autoFocus = false,
    this.minHeight = 180,
  });

  final QuillController controller;
  final FocusNode focusNode;
  final String placeholder;
  final bool readOnly;
  final bool autoFocus;
  final double minHeight;

  @override
  State<NoteQuillEditor> createState() => _NoteQuillEditorState();
}

class _NoteQuillEditorState extends State<NoteQuillEditor>
    with WidgetsBindingObserver {
  final _editorKey = GlobalKey<QuillEditorState>();
  final _scrollController = ScrollController();
  final List<Timer> _caretRevealTimers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.readOnly = widget.readOnly;
    widget.controller.addListener(_handleControllerChanged);
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant NoteQuillEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
    widget.controller.readOnly = widget.readOnly;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChanged);
    widget.focusNode.removeListener(_handleFocusChanged);
    _cancelCaretRevealTimers();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _scheduleCaretRevealBurst();
  }

  void _handleFocusChanged() {
    if (widget.focusNode.hasFocus) _scheduleCaretRevealBurst();
  }

  void _handleControllerChanged() {
    if (widget.focusNode.hasFocus) _scheduleCaretReveal();
  }

  void _cancelCaretRevealTimers() {
    for (final timer in _caretRevealTimers) {
      timer.cancel();
    }
    _caretRevealTimers.clear();
  }

  void _scheduleCaretRevealBurst() {
    if (!widget.focusNode.hasFocus) return;
    _cancelCaretRevealTimers();
    for (final delay in const [
      Duration.zero,
      Duration(milliseconds: 80),
      Duration(milliseconds: 220),
      Duration(milliseconds: 380),
    ]) {
      _scheduleCaretReveal(delay: delay);
    }
  }

  void _scheduleCaretReveal({Duration delay = Duration.zero}) {
    if (!widget.focusNode.hasFocus) return;
    if (delay == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealCaret());
      return;
    }
    final timer = Timer(delay, () {
      _caretRevealTimers.removeWhere((item) => !item.isActive);
      _revealCaret();
    });
    _caretRevealTimers.add(timer);
  }

  void _revealCaret() {
    if (!mounted || !widget.focusNode.hasFocus) return;
    final scrollable = Scrollable.maybeOf(context);
    final position = scrollable?.position;
    if (scrollable == null || position == null || !position.hasPixels) return;

    final editorState = _editorKey.currentState;
    if (editorState == null) return;

    final selection = widget.controller.selection;
    final documentLength = widget.controller.document.length;
    if (!selection.isValid || documentLength <= 0) return;
    final caretOffset = selection.extentOffset.clamp(0, documentLength - 1);

    try {
      final renderEditor =
          editorState.editableTextKey.currentState?.renderEditor;
      if (renderEditor == null) return;
      final caretRect = renderEditor.getLocalRectForCaret(
        TextPosition(offset: caretOffset, affinity: selection.affinity),
      );
      final caretTop = renderEditor.localToGlobal(caretRect.topLeft).dy;
      final caretBottom = renderEditor.localToGlobal(caretRect.bottomRight).dy;

      final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
      if (scrollableBox == null || !scrollableBox.hasSize) return;
      final viewportTop = scrollableBox.localToGlobal(Offset.zero).dy;
      var viewportBottom = scrollableBox
          .localToGlobal(Offset(0, scrollableBox.size.height))
          .dy;

      final media = MediaQuery.maybeOf(context);
      if (media != null && media.viewInsets.bottom > 0) {
        viewportBottom = math.min(
          viewportBottom,
          media.size.height - media.viewInsets.bottom,
        );
      }

      final toolbarReserve = widget.focusNode.hasFocus ? 84.0 : 0.0;
      final visibleTop = viewportTop + 12;
      final visibleBottom = viewportBottom - toolbarReserve;
      if (visibleBottom <= visibleTop) return;

      final target = noteScrollOffsetForCaret(
        currentOffset: position.pixels,
        minOffset: position.minScrollExtent,
        maxOffset: position.maxScrollExtent,
        caretTop: caretTop,
        caretBottom: caretBottom,
        visibleTop: visibleTop,
        visibleBottom: visibleBottom,
      );
      if ((target - position.pixels).abs() < 1) return;
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      // RenderEditor is not ready during a small window while Quill rebuilds.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: QuillEditor(
        key: _editorKey,
        controller: widget.controller,
        focusNode: widget.focusNode,
        scrollController: _scrollController,
        config: QuillEditorConfig(
          scrollable: false,
          autoFocus: widget.autoFocus,
          expands: false,
          minHeight: widget.minHeight,
          placeholder: widget.placeholder,
          padding: const EdgeInsets.symmetric(vertical: 8),
          enableInteractiveSelection: true,
          onTapDown: (_, _) {
            _scheduleCaretRevealBurst();
            return false;
          },
          onTapUp: (_, _) {
            _scheduleCaretRevealBurst();
            return false;
          },
          textSpanBuilder: buildNoteQuillTextSpan,
          customRecognizerBuilder: (attribute, _) {
            if (attribute.key != Attribute.link.key ||
                attribute.value is! String) {
              return null;
            }
            final link = attribute.value as String;
            return TapGestureRecognizer()
              ..onTap = () => unawaited(handleNoteInlineLinkTap(context, link));
          },
          onLaunchUrl: (link) =>
              unawaited(handleNoteInlineLinkTap(context, link)),
          linkActionPickerDelegate: (context, link, _) async {
            await handleNoteInlineLinkTap(context, link);
            return LinkMenuAction.none;
          },
          customStyleBuilder: (attribute) =>
              buildNoteQuillCustomStyle(context, attribute),
          customStyles: DefaultStyles.getInstance(context).merge(
            DefaultStyles(
              paragraph: DefaultTextBlockStyle(
                TextStyle(fontSize: 16, height: 1.5, color: textColor),
                const HorizontalSpacing(0, 0),
                const VerticalSpacing(0, 0),
                const VerticalSpacing(0, 0),
                null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
TextSpan buildNoteQuillTextSpan(
  BuildContext context,
  dynamic node,
  int nodeOffset,
  String text,
  TextStyle? style,
  GestureRecognizer? recognizer,
) {
  return TextSpan(
    text: text,
    style: _noteTextSpanStyle(context, node, style),
    recognizer: recognizer,
    mouseCursor: recognizer != null ? SystemMouseCursors.click : null,
  );
}

@visibleForTesting
TextStyle buildNoteQuillCustomStyle(BuildContext context, Attribute attribute) {
  if (attribute.key == Attribute.list.key &&
      attribute.value == Attribute.checked.value) {
    return _checkedListCompletedStyle(context);
  }
  return const TextStyle();
}

TextStyle? _noteTextSpanStyle(
  BuildContext context,
  dynamic node,
  TextStyle? style,
) {
  final resolved = _withoutSyntheticComposingUnderline(node, style);
  if (!_isNodeInCheckedList(node)) return resolved;
  return (resolved ?? const TextStyle()).merge(
    _checkedListCompletedStyle(context, baseDecoration: resolved?.decoration),
  );
}

TextStyle? _withoutSyntheticComposingUnderline(dynamic node, TextStyle? style) {
  if (style?.decoration != TextDecoration.underline) return style;
  if (_hasNodeStyleAttribute(node, Attribute.underline.key) ||
      _hasNodeStyleAttribute(node, Attribute.link.key)) {
    return style;
  }
  if (_hasNodeStyleAttribute(node, Attribute.strikeThrough.key)) {
    return style?.copyWith(decoration: TextDecoration.lineThrough);
  }
  return style?.copyWith(decoration: TextDecoration.none);
}

TextStyle _checkedListCompletedStyle(
  BuildContext context, {
  TextDecoration? baseDecoration,
}) {
  final muted = Theme.of(context).brightness == Brightness.dark
      ? AppColors.textSecondaryDark.withValues(alpha: 0.64)
      : AppColors.textSecondary.withValues(alpha: 0.74);
  final decorations = <TextDecoration>[
    if (baseDecoration != null && baseDecoration != TextDecoration.none)
      baseDecoration,
    TextDecoration.lineThrough,
  ];
  return TextStyle(
    color: muted,
    decoration: TextDecoration.combine(decorations),
    decorationColor: muted,
  );
}

bool _hasNodeStyleAttribute(dynamic node, String key) {
  try {
    final attributes = node.style.attributes;
    return attributes is Map && attributes.containsKey(key);
  } catch (_) {
    return false;
  }
}

bool _isNodeInCheckedList(dynamic node) {
  try {
    final attributes = node.parent?.style.attributes;
    if (attributes is! Map) return false;
    final list = attributes[Attribute.list.key];
    return list is Attribute && list.value == Attribute.checked.value;
  } catch (_) {
    return false;
  }
}

class NoteQuillToolbar extends StatelessWidget {
  const NoteQuillToolbar({super.key, required this.controller});

  final QuillController controller;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.surfaceDark : AppColors.surface;
    return Material(
      color: background,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: QuillSimpleToolbar(
          controller: controller,
          config: QuillSimpleToolbarConfig(
            multiRowsDisplay: false,
            showDividers: false,
            showFontFamily: false,
            showFontSize: false,
            showSmallButton: false,
            showLineHeightButton: false,
            showColorButton: false,
            showBackgroundColorButton: false,
            showClearFormat: false,
            showAlignmentButtons: false,
            showIndent: false,
            showDirection: false,
            showSearchButton: false,
            showSubscript: false,
            showSuperscript: false,
            showUndo: false,
            showRedo: false,
            showInlineCode: true,
            showCodeBlock: true,
            showHeaderStyle: true,
            showBoldButton: true,
            showItalicButton: true,
            showUnderLineButton: true,
            showStrikeThrough: true,
            showListNumbers: true,
            showListBullets: true,
            showListCheck: true,
            showQuote: true,
            showLink: false,
            color: background,
          ),
        ),
      ),
    );
  }
}

class NoteQuillAppBarActions extends StatelessWidget {
  const NoteQuillAppBarActions({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final QuillController controller;
  final FocusNode? focusNode;

  void _refocus() => focusNode?.requestFocus();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Hoàn tác',
              onPressed: controller.hasUndo
                  ? () {
                      controller.undo();
                      _refocus();
                    }
                  : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Làm lại',
              onPressed: controller.hasRedo
                  ? () {
                      controller.redo();
                      _refocus();
                    }
                  : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: 'Liên kết',
              onPressed: () => _openLinkDialog(context),
              icon: Icon(
                Icons.link,
                color: QuillTextLink.isSelected(controller)
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openLinkDialog(BuildContext context) async {
    _refocus();
    final initial = QuillTextLink.prepare(controller);
    final result = await showDialog<_NoteLinkInput>(
      context: context,
      builder: (_) =>
          _NoteLinkDialog(initialText: initial.text, initialLink: initial.link),
    );
    if (result == null) return;
    if (result.link == null) {
      _removeInlineLink();
    } else {
      QuillTextLink(result.text, result.link).submit(controller);
    }
    _refocus();
  }

  void _removeInlineLink() {
    var index = controller.selection.start;
    var length = controller.selection.end - index;
    final hasSelectedLink =
        controller.getSelectionStyle().attributes[Attribute.link.key]?.value !=
        null;
    if (hasSelectedLink) {
      final leaf = controller.document.querySegmentLeafNode(index).leaf;
      if (leaf != null) {
        final range = getLinkRange(leaf);
        index = range.start;
        length = range.end - range.start;
      }
    }
    if (length <= 0) return;
    controller.formatText(index, length, Attribute.link);
  }
}

class _NoteLinkInput {
  const _NoteLinkInput({required this.text, required this.link});

  final String text;
  final String? link;
}

class _NoteLinkDialog extends StatefulWidget {
  const _NoteLinkDialog({required this.initialText, required this.initialLink});

  final String initialText;
  final String? initialLink;

  @override
  State<_NoteLinkDialog> createState() => _NoteLinkDialogState();
}

class _NoteLinkDialogState extends State<_NoteLinkDialog> {
  late final TextEditingController _textController;
  late final TextEditingController _linkController;

  String? get _normalizedLink => normalizeNoteInlineLink(_linkController.text);

  bool get _canSubmit => _textController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _linkController = TextEditingController(text: widget.initialLink ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _notifyChanged(String _) => setState(() {});

  void _submit() {
    final link = _normalizedLink;
    if (!_canSubmit) return;
    Navigator.of(
      context,
    ).pop(_NoteLinkInput(text: _textController.text.trim(), link: link));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Thêm liên kết'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _textController,
            autofocus: widget.initialText.trim().isEmpty,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Chữ'),
            onChanged: _notifyChanged,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _linkController,
            autofocus: widget.initialText.trim().isNotEmpty,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Liên kết / ghi chú / nghĩa',
              hintText: 'VD: bỏ rơi; từ bỏ',
              helperText: 'Để trống để xóa liên kết khỏi đoạn chữ này',
            ),
            onChanged: _notifyChanged,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: const Text('Đồng ý'),
        ),
      ],
    );
  }
}

@visibleForTesting
String? normalizeNoteInlineLink(String value) {
  final link = value.trim();
  if (link.isEmpty) return null;
  return link;
}

@visibleForTesting
bool isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

@visibleForTesting
Future<void> handleNoteInlineLinkTap(BuildContext context, String value) async {
  final link = value.trim();
  if (link.isEmpty) return;
  if (isHttpUrl(link)) {
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Liên kết',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SelectableText(link, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đóng'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
