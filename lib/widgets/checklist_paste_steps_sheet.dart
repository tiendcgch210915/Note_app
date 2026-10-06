import 'package:flutter/material.dart';

Future<String?> showChecklistPasteStepsSheet(
  BuildContext context, {
  String initialText = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ChecklistPasteStepsSheet(initialText: initialText),
  );
}

class _ChecklistPasteStepsSheet extends StatefulWidget {
  final String initialText;

  const _ChecklistPasteStepsSheet({required this.initialText});

  @override
  State<_ChecklistPasteStepsSheet> createState() =>
      _ChecklistPasteStepsSheetState();
}

class _ChecklistPasteStepsSheetState extends State<_ChecklistPasteStepsSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dán nhiều bước',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: 'Mỗi dòng là một bước',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(_controller.text),
                icon: const Icon(Icons.content_paste_go_outlined),
                label: const Text('Thêm vào checklist'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
