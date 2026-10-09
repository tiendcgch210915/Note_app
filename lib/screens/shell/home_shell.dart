import 'package:flutter/material.dart';
import '../../data/auth_repository.dart';
import '../../models/note.dart';
import '../../sync/connectivity_sync.dart';
import '../../sync/sync_status_notifier.dart';
import '../../sync/sync_worker.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_routes.dart';
import '../../utils/active_session_guard.dart';
import '../../widgets/app_list_section.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_state_views.dart';
import '../../widgets/app_surface.dart';
import '../../widgets/user_avatar.dart';
import '../auth/login_screen.dart';
import '../calendar/calendar_screen.dart';
import '../checklists/checklists_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../habits/habit_create_screen.dart';
import '../habits/habits_list_screen.dart';
import '../notes/note_editor_screen.dart';
import '../notes/notes_list_screen.dart';
import '../settings/settings_screen.dart';
import '../todos/todo_create_screen.dart';
import '../todos/todos_list_screen.dart';
import 'home_shell_controller.dart';

/// Shell chính của app sau khi login — Scaffold + BottomNav 5 tab + Drawer.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  final _controller = HomeShellController.instance;

  static const _titles = ['Hôm nay', 'Todos', 'Notes', 'Thói quen', 'Lịch'];

  /// Tab Notes dùng nền be (kiểu Apple Notes) nên AppBar phải cùng màu.
  static const _notesTab = 2;

  @override
  void initState() {
    super.initState();
    _controller.currentIndex.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SyncWorker.instance.sync();
    });
  }

  @override
  void dispose() {
    _controller.currentIndex.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    final next = _controller.currentIndex.value;
    if (next == _currentIndex || !mounted) return;
    setState(() => _currentIndex = next);
  }

  Widget _screenForTab(int index) {
    switch (index) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const TodosListScreen();
      case 2:
        return const NotesListScreen();
      case 3:
        return const HabitsListScreen();
      case 4:
        return const CalendarScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget? _buildFab() {
    // FAB ẩn ở tab Today (0) và Calendar (4). Mỗi FAB có key riêng để
    // Scaffold chạy hiệu ứng thu/phóng khi đổi tab.
    switch (_currentIndex) {
      case 1:
        return FloatingActionButton(
          key: const ValueKey('fab-todo'),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TodoCreateScreen())),
          tooltip: 'Thêm việc',
          child: const Icon(Icons.add_rounded, size: 28),
        );
      case 2:
        return FloatingActionButton(
          key: const ValueKey('fab-note'),
          onPressed: _createNote,
          tooltip: 'Tạo note',
          child: const Icon(Icons.edit_rounded),
        );
      case 3:
        return FloatingActionButton(
          key: const ValueKey('fab-habit'),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const HabitCreateScreen())),
          tooltip: 'Thêm thói quen',
          child: const Icon(Icons.add_rounded, size: 28),
        );
      default:
        return null;
    }
  }

  Future<void> _createNote() async {
    final type = await showAppSheet<NoteType>(
      context: context,
      builder: (context) => AppSheetScaffold(
        title: 'Chọn loại note',
        bodyPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _NoteTypeOption(
                  icon: Icons.notes_rounded,
                  title: 'Ghi chú thường',
                  subtitle: 'Viết tự do',
                  onTap: () => Navigator.of(context).pop(NoteType.free),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NoteTypeOption(
                  icon: Icons.view_column_rounded,
                  title: 'Cornell',
                  subtitle: 'Ghi chú + gợi ý + tóm tắt',
                  onTap: () => Navigator.of(context).pop(NoteType.cornell),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (type == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(initialType: type)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _currentIndex == _notesTab
            ? context.appNoteBackground
            : null,
        title: Text(_titles[_currentIndex]),
        actions: [
          // Sync status indicator
          ValueListenableBuilder<SyncStatus>(
            valueListenable: SyncStatusNotifier.instance,
            builder: (ctx, status, _) => AnimatedSwitcher(
              duration: AppMotion.fast,
              child: _SyncIndicator(
                key: ValueKey(status.state),
                status: status,
              ),
            ),
          ),
          Builder(
            builder: (ctx) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: UserAvatar(onTap: () => Scaffold.of(ctx).openDrawer()),
            ),
          ),
        ],
      ),
      drawer: const _AppDrawer(),
      // Chuyển tab: màn mới hiện dần (không giữ 2 màn cùng lúc để tránh tranh
      // PrimaryScrollController).
      body: KeyedSubtree(
        key: ValueKey(_currentIndex),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: _screenForTab(_currentIndex),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: context.appDivider, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            if (index != _currentIndex) AppHaptics.selection();
            _controller.setTab(index);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Hôm nay',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.check_circle_outline_rounded),
              activeIcon: Icon(Icons.check_circle_rounded),
              label: 'Todos',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.sticky_note_2_outlined),
              activeIcon: Icon(Icons.sticky_note_2_rounded),
              label: 'Notes',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.local_fire_department_outlined),
              activeIcon: Icon(Icons.local_fire_department_rounded),
              label: 'Thói quen',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined),
              activeIcon: Icon(Icons.calendar_month_rounded),
              label: 'Lịch',
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFab(),
      backgroundColor: context.appBackground,
    );
  }
}

/// Ô lựa chọn loại note trong sheet "Chọn loại note".
class _NoteTypeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NoteTypeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      onTap: () {
        AppHaptics.light();
        onTap();
      },
      showShadow: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: ShapeDecoration(
              color: context.appPrimarySoft,
              shape: AppShape.squircle(AppRadius.md),
            ),
            child: Icon(icon, size: 24, color: context.appPrimary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: context.appTextSecondary),
          ),
        ],
      ),
    );
  }
}

/// Small icon in AppBar showing sync state.
class _SyncIndicator extends StatelessWidget {
  final SyncStatus status;
  const _SyncIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status.state) {
      case SyncState.syncing:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: AppSpinner(radius: 8, centered: false),
        );
      case SyncState.pendingChanges:
        return IconButton(
          icon: Badge(
            label: Text('${status.pendingCount}'),
            child: const Icon(Icons.sync_rounded, size: 22),
          ),
          tooltip: '${status.pendingCount} thay đổi chưa sync',
          onPressed: () => SyncWorker.instance.sync(),
        );
      case SyncState.error:
        return IconButton(
          icon: const Icon(
            Icons.sync_problem_rounded,
            size: 22,
            color: AppColors.danger,
          ),
          tooltip: 'Sync lỗi – nhấn để thử lại',
          onPressed: () => SyncWorker.instance.sync(),
        );
      case SyncState.idle:
        return const SizedBox.shrink();
    }
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  Future<void> _logout(BuildContext context) async {
    cancelAllSessions();
    await AuthRepository.instance.logout();
    ConnectivitySync.instance.cancelPending();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      AppRoutes.fade((_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthRepository.instance.cachedUser;
    return Drawer(
      backgroundColor: context.appBackground,
      shape: AppShape.squircleOf(
        const BorderRadius.horizontal(right: Radius.circular(AppRadius.sheet)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Phần trên cuộn được (màn thấp / chữ lớn), nút Đăng xuất ghim đáy.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: Row(
                        children: [
                          const UserAvatar(size: 52),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.displayName ?? 'Người dùng',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  user?.email ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
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
                      dividerIndent: AppListSection.iconIndent,
                      children: [
                        AppListTile(
                          icon: Icons.checklist_rounded,
                          iconColor: AppColors.success,
                          title: 'Checklists',
                          onTap: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ChecklistsScreen(),
                              ),
                            );
                          },
                        ),
                        AppListTile(
                          icon: Icons.settings_rounded,
                          iconColor: AppColors.tagSlate,
                          title: 'Cài đặt',
                          onTap: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            AppListSection(
              dividerIndent: AppListSection.iconIndent,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                AppListTile(
                  icon: Icons.logout_rounded,
                  title: 'Đăng xuất',
                  destructive: true,
                  showChevron: false,
                  onTap: () => _logout(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
