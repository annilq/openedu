import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';

/// 本地存储服务（shared_preferences 封装）。
/// 存 token、当前用户 JSON、家长设置、主题模式。
class StorageService {
  static const _keyToken = 'auth_token';
  static const _keyUser = 'current_user';
  static const _keyThemeMode = 'theme_mode';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String? getToken() => _prefs.getString(_keyToken);
  Future<void> saveToken(String token) => _prefs.setString(_keyToken, token);
  Future<void> clearToken() => _prefs.remove(_keyToken);

  String? getUserJson() => _prefs.getString(_keyUser);
  Future<void> saveUserJson(String json) => _prefs.setString(_keyUser, json);
  Future<void> clearUser() => _prefs.remove(_keyUser);

  /// 主题模式：跟随系统 / 亮色 / 暗色。
  AppThemeMode getThemeMode() {
    final raw = _prefs.getString(_keyThemeMode);
    return AppThemeMode.values.asNameMap()[raw] ?? AppThemeMode.system;
  }

  Future<void> saveThemeMode(AppThemeMode mode) =>
      _prefs.setString(_keyThemeMode, mode.name);

  Future<void> clearAll() async {
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyUser);
  }
}
