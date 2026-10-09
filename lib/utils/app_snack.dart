import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Hiện snackbar thống nhất: xoá snackbar cũ, nền đỏ khi [isError].
/// Giao diện (floating, bo góc) do `snackBarTheme` quyết định.
void showAppSnack(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : null,
      ),
    );
}
