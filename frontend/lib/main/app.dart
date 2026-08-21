import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/authentication/presentation/screens/login_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../services/auth_session/domain/providers/auth_session_provider.dart';
import '../shared/domain/models/models.dart';
import '../shared/domain/providers/core_providers.dart';
import '../shared/theme/app_theme.dart';
import '../shared/theme/theme_provider.dart';

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

    final Widget home = !_initialized
        ? const _SplashScreen()
        : _currentUser == null
            ? LoginScreen(onLoginSuccess: _onLoginSuccess)
            : _MainShell(user: _currentUser!, onLogout: _logout);

    // 覆盖子树的 platformBrightness，保证依赖系统亮度的响应式逻辑与所选
    // 主题一致（纯 Cupertino，无 Material 主题配置）。
    return CupertinoApp(
      title: '娃娃学习',
      debugShowCheckedModeBanner: false,
      theme: isDark ? AppTheme.cupertinoDark : AppTheme.cupertinoLight,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalCupertinoLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(platformBrightness: isDark ? Brightness.dark : Brightness.light),
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      child: Center(child: CupertinoActivityIndicator()),
    );
  }
}

class _MainShell extends StatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const _MainShell({required this.user, required this.onLogout});

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // 纯 Cupertino 根容器：CupertinoTabScaffold（无 Material Scaffold/SnackBar 依赖）。
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: CupertinoTheme.of(context).barBackgroundColor,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        activeColor: AppTheme.colorsOf(context).primary,
        inactiveColor: AppTheme.colorsOf(context).onSurfaceVariant,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person),
            label: '我的',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return HomeScreen(user: widget.user, onLogout: widget.onLogout);
          default:
            return ProfileScreen(user: widget.user, onLogout: widget.onLogout);
        }
      },
    );
  }
}