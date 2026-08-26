import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../features/authentication/presentation/screens/login_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../services/auth_session/domain/providers/auth_session_provider.dart';
import '../shared/domain/models/models.dart';
import '../shared/domain/providers/core_providers.dart';
import '../shared/theme/app_theme.dart';
import '../shared/theme/theme_provider.dart';
import '../shared/widgets/app_loading.dart';

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  UserModel? _currentUser;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // 推迟到首帧构建完成后，避免在 build 阶段同步修改 StateProvider
    // 导致 framework 的 !_dirty 断言失败。
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
  }

  Future<void> _restoreSession() async {
    final storage = ref.read(storageServiceProvider);
    final userJson = storage.getUserJson();
    if (userJson != null) {
      try {
        final map = jsonDecode(userJson) as Map<String, dynamic>;
        final user = UserModel.fromJson(map);
        ref.read(currentUserProvider.notifier).state = user;
        if (mounted) {
          setState(() {
            _currentUser = user;
            _initialized = true;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _initialized = true);
      }
    } else if (mounted) {
      setState(() => _initialized = true);
    }
  }

  Future<void> _onLoginSuccess() async {
    final storage = ref.read(storageServiceProvider);
    final userJson = storage.getUserJson();
    if (userJson != null) {
      try {
        final map = jsonDecode(userJson) as Map<String, dynamic>;
        final user = UserModel.fromJson(map);
        ref.read(currentUserProvider.notifier).state = user;
        if (mounted) setState(() => _currentUser = user);
      } catch (_) {
        // ignore parse errors
      }
    }
  }

  Future<void> _logout() async {
    final storage = ref.read(storageServiceProvider);
    await storage.clearAll();
    ref.read(currentUserProvider.notifier).state = null;
    if (mounted) setState(() => _currentUser = null);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final isDark = resolveBrightness(themeMode, systemBrightness) ==
        Brightness.dark;
    final active = isDark ? AppTheme.dark : AppTheme.light;

    final Widget home = !_initialized
        ? const _SplashScreen()
        : _currentUser == null
            ? LoginScreen(onLoginSuccess: _onLoginSuccess)
            : HomeScreen(user: _currentUser!, onLogout: _logout);

    return ShadApp.custom(
      theme: AppTheme.shadFor(false),
      darkTheme: AppTheme.shadFor(true),
      themeMode: appThemeModeToMaterial(themeMode),
      appBuilder: (context) => CupertinoApp(
          title: '娃娃学习',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.cupertinoFor(isDark),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: [
            GlobalShadLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            // cupertino_ui 自带：GlobalCupertinoLocalizations + GlobalWidgetsLocalizations
            ...GlobalCupertinoLocalizations.delegates,
          ],
          builder: (context, child) => ShadAppBuilder(
            backgroundColor: active.surfaceContainerLow,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                platformBrightness:
                    isDark ? Brightness.dark : Brightness.light,
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: home,
        ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return SizedBox.expand(
      child: ColoredBox(
        color: app.surface,
        child: const Center(child: AppLoading()),
      ),
    );
  }
}