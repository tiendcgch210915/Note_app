import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
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
import 'utils/app_navigator.dart';
import 'utils/focus_session_controller.dart';
import 'widgets/focus_session_banner.dart';
import 'widgets/frog_completion_celebration.dart';

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

    // Register post-pull repair without importing TodosRepository in the sync
    // worker (circular dependency guard).
    SyncWorker.registerPostPullHook(
      TodosRepository.instance.ensureAllRecurrenceInstances,
    );

    // 6. Listen for 401 → force back to login
    needsReLoginNotifier.stream.listen((_) {
      FocusSessionController.instance.cancel();
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
        });
      }
    });

    // 7. Repair legacy recurrence from Drift first, then sync with the server.
    if (isAuth) {
      await TodosRepository.instance.ensureAllRecurrenceInstances();
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
            navigatorKey: rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: const [Locale('vi'), Locale('en')],
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            builder: (context, child) => FrogCompletionCelebrationHost(
              child: FocusSessionBannerHost(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
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
