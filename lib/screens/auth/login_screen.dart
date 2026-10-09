import 'package:flutter/material.dart';
import '../../data/api_exception.dart';
import '../../data/auth_repository.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_routes.dart';
import '../../utils/app_snack.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/primary_button.dart';
import '../shell/home_shell.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final emailMissing = _email.text.trim().isEmpty;
    final passwordMissing = _password.text.trim().isEmpty;
    if (emailMissing || passwordMissing) {
      AppHaptics.heavy();
      setState(() {
        _emailError = emailMissing ? 'Vui lòng nhập email' : null;
        _passwordError = passwordMissing ? 'Vui lòng nhập mật khẩu' : null;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final user = await AuthRepository.instance.login(
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      showAppSnack(context, 'Xin chào ${user.displayName ?? user.email}');
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
                      const SizedBox(height: 24),
                      const AuthBrandHeader(
                        title: 'Productivity',
                        subtitle: 'Todo · Note · Habit · Checklist',
                      ),
                      const SizedBox(height: 40),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                        onChanged: (_) {
                          if (_emailError != null) {
                            setState(() => _emailError = null);
                          }
                        },
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
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
                        hintText: 'Mật khẩu',
                        errorText: _passwordError,
                        autofillHints: const [AutofillHints.password],
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
                        label: 'Đăng nhập',
                        loading: _loading,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          );
                        },
                        child: const Text('Chưa có tài khoản? Đăng ký'),
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
