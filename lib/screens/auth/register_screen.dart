import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/auth_repository.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_routes.dart';
import '../../utils/app_snack.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/primary_button.dart';
import '../shell/home_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  String? _nameError;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final nameMissing = _name.text.trim().isEmpty;
    final emailMissing = _email.text.trim().isEmpty;
    final passwordMissing = _password.text.trim().isEmpty;
    final passwordShort = !passwordMissing && _password.text.length < 8;
    if (nameMissing || emailMissing || passwordMissing || passwordShort) {
      AppHaptics.heavy();
      setState(() {
        _nameError = nameMissing ? 'Vui lòng nhập tên hiển thị' : null;
        _emailError = emailMissing ? 'Vui lòng nhập email' : null;
        _passwordError = passwordMissing
            ? 'Vui lòng nhập mật khẩu'
            : passwordShort
            ? 'Mật khẩu tối thiểu 8 ký tự'
            : null;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final user = await AuthRepository.instance.register(
        email: _email.text,
        password: _password.text,
        displayName: _name.text,
      );
      if (!mounted) return;
      showAppSnack(
        context,
        'Đăng ký thành công, chào ${user.displayName ?? user.email}!',
      );
      Navigator.of(
        context,
      ).pushReplacement(AppRoutes.fade((_) => const HomeShell()));
    } on ApiException catch (e) {
      if (!mounted) return;
      AppHaptics.heavy();
      showAppSnack(context, e.vnMessage, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      const Center(
                        child: AuthBrandHeader(
                          title: 'Tạo tài khoản',
                          logoSize: 64,
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (_) => _emailFocus.requestFocus(),
                        onChanged: (_) {
                          if (_nameError != null) {
                            setState(() => _nameError = null);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Tên hiển thị',
                          errorText: _nameError,
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _email,
                        focusNode: _emailFocus,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                        onChanged: (_) {
                          if (_emailError != null) {
                            setState(() => _emailError = null);
                          }
                        },
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          hintText: 'Email',
                          errorText: _emailError,
                          prefixIcon: const Icon(Icons.alternate_email_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AuthPasswordField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        hintText: 'Mật khẩu (≥ 8 ký tự)',
                        errorText: _passwordError,
                        autofillHints: const [
                          AutofillHints.newPassword,
                          AutofillHints.password,
                        ],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        onChanged: (_) {
                          if (_passwordError != null) {
                            setState(() => _passwordError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: 'Tạo tài khoản',
                        loading: _loading,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
