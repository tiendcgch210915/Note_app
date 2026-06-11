import 'package:flutter/material.dart';
import 'data/api_client.dart';
import 'data/auth_repository.dart';
import 'data/auth_storage.dart';
import 'data/local/database.dart';
import 'data/todos_repository.dart';
import 'screens/auth/login_screen.dart';
import 'screens/shell/home_shell.dart';
import 'data/remote/api_client_dio.dart';
import 'sync/connectivity_sync.dart';
import 'sync/sync_worker.dart';
import 'theme/app_theme.dart';

/// Controller cho ThemeMode — expose qua AppThemeScope (InheritedWidget).
class AppThemeController {
  final ValueNotifier<ThemeMode> mode;
  AppThemeController({ThemeMode initial = ThemeMode.dark})
    : mode = ValueNotifier(initial);
}

class AppThemeScope extends InheritedWidget {
  final AppThemeController controller;

  const AppThemeScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static AppThemeController? of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    return scope?.controller;
  }

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Root widget cho ứng dụng.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _theme = AppThemeController();
  bool _isReady = false;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Trigger sync when app comes back to foreground
    if (state == AppLifecycleState.resumed && _isAuthenticated) {
      SyncWorker.instance.sync();
    }
  }

  Future<void> _bootstrap() async {
    // 1. Hydrate token cache từ secure storage
    await AuthStorage.instance.init();

    // 2. Init Drift database (creates tables on first launch)
    AppDatabase.instance; // trigger singleton init

    // 3. Health probe (best-effort, không block nếu fail)
    await ApiClient.instance.healthCheck();

    // 4. Check token tồn tại
    final isAuth = await AuthRepository.instance.isAuthenticated();

    if (!mounted) return;
    setState(() {
      _isAuthenticated = isAuth;
      _isReady = true;
    });

    // 5. Start connectivity listener (will trigger sync on reconnect)
    await ConnectivitySync.instance.init();

    // Register post-pull hook so SyncWorker can trigger recurrence instance
    // generation without importing TodosRepository (circular dep guard).
    SyncWorker.registerPostPullHook(
      TodosRepository.instance.ensureAllRecurrenceInstances,
    );

    // 6. Listen for 401 → force back to login
    needsReLoginNotifier.stream.listen((_) {
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
        });
      }
    });

    // 7. If authenticated, trigger initial pull to populate Drift
    if (isAuth) {
      SyncWorker.instance.sync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _theme.mode.dispose();
    ConnectivitySync.instance
        .dispose(); // fire-and-forget (returns Future, ignore result)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      controller: _theme,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _theme.mode,
        builder: (ctx, mode, _) {
          return MaterialApp(
            title: 'Productivity',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: _isReady
                ? (_isAuthenticated ? const HomeShell() : const LoginScreen())
                : const _BootstrapLoading(),
          );
        },
      ),
    );
  }
}

class _BootstrapLoading extends StatelessWidget {
  const _BootstrapLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt, size: 56, color: Color(0xFF4F46E5)),
            SizedBox(height: 16),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
