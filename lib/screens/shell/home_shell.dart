import 'package:flutter/material.dart';
import '../../data/auth_repository.dart';
import '../../sync/connectivity_sync.dart';
import '../../sync/sync_status_notifier.dart';
import '../../sync/sync_worker.dart';
import '../../theme/app_colors.dart';
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

/// Shell chính của app sau khi login — Scaffold + BottomNav 5 tab + Drawer.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  static const _titles = ['Hôm nay', 'Todos', 'Notes', 'Thói quen', 'Lịch'];

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
    // FAB ẩn ở tab Today (0) và Calendar (4).
    switch (_currentIndex) {
      case 1:
        return FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TodoCreateScreen()),
          ),
          tooltip: 'Thêm việc',
          child: const Icon(Icons.add),
        );
      case 2:
        return FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
          ),
          tooltip: 'Tạo note',
          child: const Icon(Icons.edit_outlined),
        );
      case 3:
        return FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HabitCreateScreen()),
          ),
          tooltip: 'Thêm thói quen',
          child: const Icon(Icons.add),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        actions: [
          // Sync status indicator
          ValueListenableBuilder<SyncStatus>(
            valueListenable: SyncStatusNotifier.instance,
            builder: (ctx, status, _) => _SyncIndicator(status: status),
          ),
          Builder(
            builder: (ctx) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => Scaffold.of(ctx).openDrawer(),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    (AuthRepository.instance.cachedUser?.displayName ?? AuthRepository.instance.cachedUser?.email ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: const _AppDrawer(),
      body: _screenForTab(_currentIndex),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Hôm nay',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            activeIcon: Icon(Icons.check_circle),
            label: 'Todos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sticky_note_2_outlined),
            activeIcon: Icon(Icons.sticky_note_2),
            label: 'Notes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_fire_department_outlined),
            activeIcon: Icon(Icons.local_fire_department),
            label: 'Thói quen',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            activeIcon: Icon(Icons.calendar_month),
            label: 'Lịch',
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
    );
  }

}

/// Small icon in AppBar showing sync state.
class _SyncIndicator extends StatelessWidget {
  final SyncStatus status;
  const _SyncIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status.state) {
      case SyncState.syncing:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case SyncState.pendingChanges:
        return IconButton(
          icon: Badge(
            label: Text('${status.pendingCount}'),
            child: const Icon(Icons.sync, size: 20),
          ),
          tooltip: '${status.pendingCount} thay đổi chưa sync',
          onPressed: () => SyncWorker.instance.sync(),
        );
      case SyncState.error:
        return IconButton(
          icon: const Icon(Icons.sync_problem, size: 20, color: AppColors.danger),
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
    await AuthRepository.instance.logout();
    ConnectivitySync.instance.cancelPending();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthRepository.instance.cachedUser;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      (user?.displayName ?? user?.email ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Người dùng',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        Text(user?.email ?? '', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Checklists'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChecklistsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Cài đặt'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text('Đăng xuất', style: TextStyle(color: AppColors.danger)),
              onTap: () => _logout(context),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
