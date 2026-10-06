import 'package:flutter/material.dart';

class NoteTextEditingController extends TextEditingController {
  NoteTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return TextSpan(style: style, text: text);
  }
}
