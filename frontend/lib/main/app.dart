import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/authentication/presentation/screens/login_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../services/auth_session/domain/providers/auth_session_provider.dart';
import '../shared/data/local/storage_service.dart';
import '../shared/domain/models/models.dart';
import '../shared/domain/providers/core_providers.dart';
import '../shared/theme/app_theme.dart';

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
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final storage = ref.read(storageServiceProvider);
    final userJson = storage.getUserJson();
    if (userJson != null) {
      try {
        final map = jsonDecode(userJson) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(map);
        ref.read(currentUserProvider.notifier).state = _currentUser;
      } catch (_) {
        _currentUser = null;
      }
    }
    if (mounted) setState(() => _initialized = true);
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
    if (!_initialized) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: AppTheme.light.colorScheme.surface,
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: '娃娃学习',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _currentUser == null
          ? LoginScreen(onLoginSuccess: _onLoginSuccess)
          : _MainShell(user: _currentUser!, onLogout: _logout),
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
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(user: widget.user, onLogout: widget.onLogout),
          ProfileScreen(user: widget.user, onLogout: widget.onLogout),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
