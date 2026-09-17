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
  ///
  /// [receiveTimeout] 可覆写接收超时——流式端点（出题 / 伴学）耗时远超普通请求，
  /// 沿用 BaseOptions 的短超时会在生成中途掐断流，表现为「少题」且难以定位。
  Stream<Uint8List> streamPost(String path,
      {Map<String, dynamic>? body, Duration? receiveTimeout});

  /// 二进制 POST：返回原始字节（如打印导出的 PDF）。
  ///
  /// 非 2xx 时必须保留后端错误体里的 code / message——二进制响应的错误体
  /// 仍是 JSON 文本，吞掉它会把「越权 403」和「字体缺失 503」都挤成
  /// 「请求失败 (xxx)」，家长无法判断该重试还是该找人。
  Future<Uint8List> postBytes(String path, {Map<String, dynamic>? body});
}
