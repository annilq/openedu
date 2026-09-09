import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/storage_service.dart';
import '../domain/providers/core_providers.dart';
import 'app_theme.dart';

/// 主题模式（跟随系统 / 亮色 / 暗色），持久化到本地存储。
///
/// 读取：[ref.watch(themeModeProvider)] 得到当前 [AppThemeMode]。
/// 写入：[ref.read(themeModeProvider.notifier).setMode(AppThemeMode.dark)]。
class ThemeModeController extends StateNotifier<AppThemeMode> {
  ThemeModeController(this._storage, AppThemeMode initial) : super(initial);

  final StorageService _storage;

  Future<void> setMode(AppThemeMode mode) async {
    state = mode;
    await _storage.saveThemeMode(mode);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, AppThemeMode>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return ThemeModeController(storage, storage.getThemeMode());
});

/// 用户模式（家长工作台 / 娃娃学习台），持久化到本地存储。
///
/// 读取：[ref.watch(userModeProvider)] 得到当前 [AppUserMode]。
/// 写入：[ref.read(userModeProvider.notifier).setMode(AppUserMode.child)]。
class UserModeController extends StateNotifier<AppUserMode> {
  UserModeController(this._storage, AppUserMode initial) : super(initial);

  final StorageService _storage;

  Future<void> setMode(AppUserMode mode) async {
    state = mode;
    await _storage.saveUserMode(mode);
  }
}

final userModeProvider =
    StateNotifierProvider<UserModeController, AppUserMode>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return UserModeController(storage, storage.getUserMode());
});

/// 控件密度（compact / normal），持久化到本地存储。
///
/// **默认 [AppDensity.compact]**（parent 32 / child 40）。与亮暗、用户模式正交：
/// 三者共同喂给 `AppTheme.shadFor(isDark, mode, density)`，决定 shadcn 主题里的
/// 控件高度，让裸 `ShadButton` / `ShadInput` 与 `App*` 组件严格同高。
///
/// 读取：[ref.watch(densityProvider)]；写入：[ref.read(densityProvider.notifier)]。
class DensityController extends StateNotifier<AppDensity> {
  DensityController(this._storage, AppDensity initial) : super(initial);

  final StorageService _storage;

  Future<void> setDensity(AppDensity density) async {
    state = density;
    await _storage.saveDensity(density);
  }

  /// 在 compact / normal 之间切换。
  Future<void> toggle() async =>
      setDensity(state == AppDensity.compact
          ? AppDensity.normal
          : AppDensity.compact);
}

final densityProvider =
    StateNotifierProvider<DensityController, AppDensity>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return DensityController(storage, storage.getDensity());
});
