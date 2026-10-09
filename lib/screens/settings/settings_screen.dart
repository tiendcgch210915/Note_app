import 'package:flutter/material.dart';
import '../../app.dart';
import '../../data/auth_repository.dart';
import '../../models/user.dart';
import '../../theme/app_colors.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_routes.dart';
import '../../utils/app_snack.dart';
import '../../utils/active_session_guard.dart';
import '../../widgets/app_list_section.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/user_avatar.dart';
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
    cancelAllSessions();
    await AuthRepository.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      AppRoutes.fade((_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: _loading
          ? const AppSpinner()
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Row(
                    children: [
                      const UserAvatar(size: 64),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _user?.displayName ?? 'Người dùng',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _user?.email ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AppListSection(
                  header: 'Tài khoản',
                  dividerIndent: AppListSection.iconIndent,
                  children: [
                    AppListTile(
                      icon: Icons.person_rounded,
                      title: 'Hồ sơ',
                      onTap: () => showAppSnack(
                        context,
                        'Tính năng đang được phát triển',
                      ),
                    ),
                    AppListTile(
                      icon: Icons.public_rounded,
                      iconColor: AppColors.tagCyan,
                      title: 'Múi giờ',
                      value: _user?.timezone ?? 'Asia/Ho_Chi_Minh',
                    ),
                  ],
                ),
                AppListSection(
                  header: 'Giao diện & thông báo',
                  dividerIndent: AppListSection.iconIndent,
                  children: [
                    if (controller != null)
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: controller.mode,
                        builder: (context, mode, _) {
                          final isDark = mode == ThemeMode.dark;
                          void toggle(bool v) {
                            AppHaptics.selection();
                            controller.mode.value = v
                                ? ThemeMode.dark
                                : ThemeMode.light;
                          }

                          return AppListTile(
                            icon: Icons.dark_mode_rounded,
                            iconColor: AppColors.tagPurple,
                            title: 'Chế độ tối',
                            onTap: () => toggle(!isDark),
                            trailing: Switch(value: isDark, onChanged: toggle),
                          );
                        },
                      ),
                    AppListTile(
                      icon: Icons.notifications_rounded,
                      iconColor: AppColors.tagAmber,
                      title: 'Thông báo nhắc nhở',
                      subtitle: 'Chỉ lưu local — chưa sync server',
                      onTap: () {
                        AppHaptics.selection();
                        setState(() => _notif = !_notif);
                      },
                      trailing: Switch(
                        value: _notif,
                        onChanged: (v) {
                          AppHaptics.selection();
                          setState(() => _notif = v);
                        },
                      ),
                    ),
                  ],
                ),
                AppListSection(
                  header: 'Giới thiệu',
                  dividerIndent: AppListSection.iconIndent,
                  children: [
                    AppListTile(
                      icon: Icons.info_rounded,
                      iconColor: AppColors.tagSlate,
                      title: 'Về ứng dụng',
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'Productivity',
                          applicationVersion: '1.0.0',
                          applicationIcon: Icon(
                            Icons.task_alt_rounded,
                            color: context.appPrimary,
                            size: 32,
                          ),
                          children: const [
                            Text(
                              'App năng suất cá nhân: Todo, Note, Habit, Checklist.',
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                AppListSection(
                  dividerIndent: AppListSection.iconIndent,
                  children: [
                    AppListTile(
                      icon: Icons.logout_rounded,
                      title: 'Đăng xuất',
                      destructive: true,
                      showChevron: false,
                      onTap: _logout,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
