import 'package:flutter/material.dart';
import '../../app.dart';
import '../../data/auth_repository.dart';
import '../../models/user.dart';
import '../../theme/app_colors.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notif = true;
  User? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await AuthRepository.instance.currentUser();
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await AuthRepository.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeScope.of(context);
    final isDark = controller?.mode.value == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          (_user?.displayName ?? _user?.email ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 24),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _user?.displayName ?? 'Người dùng',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(_user?.email ?? '', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Hồ sơ'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Backend chưa hỗ trợ update profile')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('Múi giờ'),
                  trailing: Text(_user?.timezone ?? 'Asia/Ho_Chi_Minh',
                      style: const TextStyle(fontSize: 13)),
                ),
                SwitchListTile(
                  value: isDark,
                  onChanged: (v) =>
                      controller?.mode.value = v ? ThemeMode.dark : ThemeMode.light,
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Chế độ tối'),
                ),
                SwitchListTile(
                  value: _notif,
                  onChanged: (v) => setState(() => _notif = v),
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Thông báo nhắc nhở'),
                  subtitle: const Text('Chỉ lưu local — chưa sync server'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Về ứng dụng'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'Productivity',
                      applicationVersion: '1.0.0',
                      applicationIcon: const Icon(Icons.task_alt,
                          color: AppColors.primary, size: 32),
                      children: const [
                        Text('App năng suất cá nhân: Todo, Note, Habit, Checklist.'),
                      ],
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.danger),
                  title: const Text('Đăng xuất',
                      style: TextStyle(color: AppColors.danger)),
                  onTap: _logout,
                ),
              ],
            ),
    );
  }
}
