import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储服务（shared_preferences 封装）。
/// 存 token、当前用户 JSON、家长设置。
class StorageService {
  static const _keyToken = 'auth_token';
  static const _keyUser = 'current_user';

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

  Future<void> clearAll() async {
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyUser);
  }
}
