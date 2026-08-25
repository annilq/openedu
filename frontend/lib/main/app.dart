import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../features/authentication/presentation/screens/login_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
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

    final Widget home = !_initialized
        ? const _SplashScreen()
        : _currentUser == null
            ? LoginScreen(onLoginSuccess: _onLoginSuccess)
            : _MainShell(user: _currentUser!, onLogout: _logout);

    // Shadcn + Cupertino 混合根：ShadApp.custom 提供 ShadTheme 上下文，
    // appBuilder 内用 CupertinoApp 承载业务页，ShadAppBuilder 挂 ShadToaster/Sonner
    // 并铺背景色；MediaQuery 覆盖 platformBrightness 保证与所选主题一致。
    return ShadApp.custom(
      theme: AppTheme.shadThemeData(AppTheme.light),
      darkTheme: AppTheme.shadThemeData(AppTheme.dark),
      themeMode: appThemeModeToMaterial(themeMode),
      appBuilder: (context) => CupertinoApp(
        title: '娃娃学习',
        debugShowCheckedModeBanner: false,
        theme: isDark ? AppTheme.cupertinoDark : AppTheme.cupertinoLight,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: [
          GlobalShadLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          // cupertino_ui 自带：GlobalCupertinoLocalizations + GlobalWidgetsLocalizations
          ...GlobalCupertinoLocalizations.delegates,
        ],
        builder: (context, child) => ShadAppBuilder(
          backgroundColor:
              isDark ? AppTheme.dark.surface : AppTheme.light.surface,
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

class _MainShell extends StatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const _MainShell({required this.user, required this.onLogout});

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;

  static const _items = <_NavItem>[
    _NavItem(icon: LucideIcons.house, label: '首页'),
    _NavItem(icon: LucideIcons.userRound, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final screens = <Widget>[
      HomeScreen(user: widget.user, onLogout: widget.onLogout),
      ProfileScreen(user: widget.user, onLogout: widget.onLogout),
    ];

    // 自建 Shad 底部导航：IndexedStack 保状态 + 底部 ShadCard 容器内
    // Row[ShadButton.ghost 数组，选中用 primary 色]。
    return SizedBox.expand(
      child: ColoredBox(
        color: app.surface,
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _index,
                children: screens,
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: ShadCard(
                  backgroundColor: app.surfaceContainerLow,
                  border: ShadBorder.all(
                    color: app.outline,
                    width: 1,
                    radius: BorderRadius.circular(AppRadius.button),
                  ),
                  shadows: const [],
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        Expanded(
                          child: _NavItemButton(
                            icon: _items[i].icon,
                            label: _items[i].label,
                            selected: _index == i,
                            onTap: () => setState(() => _index = i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _NavItemButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItemButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final color = selected ? app.primary : app.onSurfaceVariant;
    return ShadButton.ghost(
      width: double.infinity,
      height: 52,
      onPressed: onTap,
      backgroundColor:
          selected ? app.primaryContainer : const Color(0x00000000),
      hoverBackgroundColor:
          selected ? app.primaryContainer : app.surfaceContainerHigh,
      pressedBackgroundColor:
          selected ? app.primaryContainer : app.surfaceContainer,
      foregroundColor: color,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: text.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}