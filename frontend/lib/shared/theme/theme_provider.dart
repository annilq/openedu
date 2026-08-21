import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/storage_service.dart';
import '../domain/providers/core_providers.dart';

/// 主题模式（跟随系统 / 亮色 / 暗色），持久化到本地存储。
///
/// 读取：[ref.watch(themeModeProvider)] 得到当前 [ThemeMode]。
/// 写入：[ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark)]。
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._storage, ThemeMode initial) : super(initial);

  final StorageService _storage;

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _storage.saveThemeMode(mode);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return ThemeModeController(storage, storage.getThemeMode());
});