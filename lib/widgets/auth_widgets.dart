import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Logo + tên app + dòng mô tả, dùng chung cho màn đăng nhập/đăng ký.
class AuthBrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double logoSize;

  const AuthBrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.logoSize = 72,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: ShapeDecoration(
            color: AppColors.accentFill,
            shape: AppShape.squircle(logoSize * 0.3),
            shadows: AppShadows.card(context.isDark),
          ),
          child: Icon(
            Icons.task_alt_rounded,
            size: logoSize * 0.55,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: context.appTextSecondary),
          ),
        ],
      ],
    );
  }
}

/// Ô mật khẩu có nút hiện/ẩn. Vẫn là một [TextField] thuần (autofill, test).
class AuthPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final List<String> autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final String? errorText;

  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.autofillHints,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.errorText,
  });

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscure,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: widget.hintText,
        errorText: widget.errorText,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
