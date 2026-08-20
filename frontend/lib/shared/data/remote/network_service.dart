import 'dart:convert';

/// 网络服务抽象：统一 get/post 接口。
/// 外层（data 层）通过此抽象与后端通信，不直接依赖 Dio。
abstract class NetworkService {
  Future<dynamic> get(String path, {Map<String, dynamic>? query});
  Future<dynamic> post(String path, {Map<String, dynamic>? body});
  Future<dynamic> put(String path, {Map<String, dynamic>? body});
  Future<dynamic> delete(String path);
}
