import 'dart:typed_data';

/// 网络服务抽象：统一 get/post 接口。
/// 外层（data 层）通过此抽象与后端通信，不直接依赖 Dio。
abstract class NetworkService {
  Future<dynamic> get(String path, {Map<String, dynamic>? query});
  Future<dynamic> post(String path, {Map<String, dynamic>? body});
  Future<dynamic> put(String path,
      {Map<String, dynamic>? query, Map<String, dynamic>? body});
  Future<dynamic> delete(String path, {Map<String, dynamic>? body});

  /// SSE 流式 POST：返回原始字节流（text/event-stream），由调用方按 SSE 协议解析。
  /// 复用 Dio 拦截器（自动注入 Authorization、错误统一转 AppException）。
  Stream<Uint8List> streamPost(String path, {Map<String, dynamic>? body});
}
