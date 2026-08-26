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
