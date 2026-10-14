import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';

/// 本地存储服务（shared_preferences 封装）。
/// 存 token、当前用户 JSON、教师设置、主题模式。
class StorageService {
  static const _keyToken = 'auth_token';
  static const _keyUser = 'current_user';
  static const _keyThemeMode = 'theme_mode';
  static const _keyUserMode = 'user_mode';
  static const _keyDensity = 'ui_density';
  static const _keySidebarCollapsed = 'sidebar_collapsed';
  static const _keyTeacherPagePath = 'teacher_last_page_path';
  static const _keyChildTab = 'child_last_tab';

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

  /// 用户模式：教师工作台 / 学生学习台（双模式，ADR-0014）。
  AppUserMode getUserMode() {
    final raw = _prefs.getString(_keyUserMode);
    return AppUserMode.values.asNameMap()[raw] ?? AppUserMode.teacher;
  }

  Future<void> saveUserMode(AppUserMode mode) =>
      _prefs.setString(_keyUserMode, mode.name);

  /// 控件密度（compact / normal），默认 [AppDensity.compact]（teacher 32 / child 40）。
  AppDensity getDensity() {
    final raw = _prefs.getString(_keyDensity);
    return AppDensity.values.asNameMap()[raw] ?? AppControl.defaultDensity;
  }

  Future<void> saveDensity(AppDensity density) =>
      _prefs.setString(_keyDensity, density.name);

  bool getSidebarCollapsed() =>
      _prefs.getBool(_keySidebarCollapsed) ?? false;
  Future<void> saveSidebarCollapsed(bool v) =>
      _prefs.setBool(_keySidebarCollapsed, v);

  /// 教师端上次所在页面路径（ticket 12）：重启后由壳恢复落点。
  String? getLastTeacherPagePath() => _prefs.getString(_keyTeacherPagePath);
  Future<void> saveLastTeacherPagePath(String path) =>
      _prefs.setString(_keyTeacherPagePath, path);
  Future<void> clearLastTeacherPagePath() =>
      _prefs.remove(_keyTeacherPagePath);

  /// 学生端上次所在页签下标（ticket 12）：重启后由壳恢复页签。
  int? getLastChildTab() => _prefs.getInt(_keyChildTab);
  Future<void> saveLastChildTab(int index) =>
      _prefs.setInt(_keyChildTab, index);
  Future<void> clearLastChildTab() => _prefs.remove(_keyChildTab);

  Future<void> clearAll() async {
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyUser);
    // ticket 12：登出同时清空已存的落点，避免把上个账号的页面带进下个账号。
    await _prefs.remove(_keyTeacherPagePath);
    await _prefs.remove(_keyChildTab);
  }
}
