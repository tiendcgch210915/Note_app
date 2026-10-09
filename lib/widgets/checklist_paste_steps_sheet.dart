import 'package:flutter/material.dart';

import 'app_sheet.dart';
import 'primary_button.dart';

Future<String?> showChecklistPasteStepsSheet(
  BuildContext context, {
  String initialText = '',
}) {
  return showAppSheet<String>(
    context: context,
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
      // Cuộn được để khi bàn phím mở trên màn thấp, sheet không bị tràn đáy.
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSheetHeader(
              title: 'Dán nhiều bước',
              subtitle: 'Mỗi dòng sẽ trở thành một bước',
              padding: EdgeInsets.only(bottom: 12),
            ),
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
            PrimaryButton(
              label: 'Thêm vào checklist',
              icon: Icons.content_paste_go_outlined,
              onPressed: () => Navigator.of(context).pop(_controller.text),
            ),
          ],
        ),
      ),
    );
  }
}
