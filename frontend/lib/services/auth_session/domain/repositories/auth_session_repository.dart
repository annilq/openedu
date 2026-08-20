import '../../../../shared/domain/models/models.dart';

/// 认证会话仓库抽象：管理当前登录用户的 token 和信息。
abstract class AuthSessionRepository {
  Future<String?> getToken();
  Future<UserModel?> getCurrentUser();
  Future<void> saveSession(String token, UserModel user);
  Future<void> clearSession();
  Future<UserModel?> fetchMe(); // 从后端获取当前用户
}
