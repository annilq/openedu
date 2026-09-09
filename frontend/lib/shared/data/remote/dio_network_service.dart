import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../exceptions/app_exception.dart';
import '../../../configs/app_config.dart';
import '../local/storage_service.dart';
import 'network_service.dart';

/// Dio 网络服务实现。
/// 拦截器 1: Token 注入 — 从 StorageService 取 JWT 放入 Authorization。
/// 拦截器 2: 错误统一 — 非 2xx 按 E-Q2 统一错误体解析，抛出带 code 的 HttpException。
class DioNetworkService implements NetworkService {
  final StorageService _storage;
  late final Dio _dio;

  DioNetworkService(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _setupInterceptors();
  }

  void _setupInterceptors() {
    // Token 拦截器
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _storage.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  /// 把 DioException 统一转为应用异常（HttpException / UnauthorizedException）。
  Never _handleError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 401) {
      throw UnauthorizedException();
    }
    final parsed = _extractError(e);
    throw HttpException(
      parsed.message,
      statusCode: statusCode,
      code: parsed.code,
    );
  }

  _ParsedError _extractError(DioException e) {
    final response = e.response;
    final data = response?.data;
    final code = data is Map ? data['code']?.toString() : null;
    final message = data is Map ? data['message']?.toString() : null;
    if (code != null && message != null && message.isNotEmpty) {
      return _ParsedError(code: code, message: message);
    }
    // 向后兼容老的 FastAPI / Starlette 默认格式
    if (data is Map) {
      final detail = data['detail'];
      if (detail != null) {
        final msg = detail is Map
            ? (detail['msg']?.toString() ?? detail.toString())
            : detail.toString();
        return _ParsedError(code: code, message: msg);
      }
    }
    // 响应为空：连接层失败（超时 / 连接被拒 / 域名解析 / 证书），把 Dio 真实原因透出，
    // 避免「请求失败 (-1)」死局——此时请求根本没到后端，需在客户端排查网络/地址。
    if (response == null) {
      return _ParsedError(code: code, message: _describeConnectionFailure(e));
    }
    return _ParsedError(
      code: code,
      message: '请求失败 (${response.statusCode})',
    );
  }

  /// 把连接层失败翻译成可读文案，并附上底层 OS 错误与目标地址，方便定位「-1 无日志」类问题。
  String _describeConnectionFailure(DioException e) {
    final underlying = e.error?.toString().replaceAll('\n', ' ').trim();
    final detail =
        underlying != null && underlying.isNotEmpty ? '（$underlying）' : '';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '请求超时（${e.type.name}），请确认网络与后端状态';
      case DioExceptionType.connectionError:
        return '无法连接服务器$detail，请确认后端已启动且地址可达：${AppConfig.apiBaseUrl}';
      case DioExceptionType.badCertificate:
        return 'SSL 证书错误，无法建立安全连接';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        return '请求失败（无响应$detail）';
    }
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    try {
      final r = await _dio.get(path, queryParameters: query);
      return r.data;
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    try {
      final r = await _dio.post(path, data: body);
      return r.data;
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<dynamic> put(String path,
      {Map<String, dynamic>? query, Map<String, dynamic>? body}) async {
    try {
      final r = await _dio.put(path, queryParameters: query, data: body);
      return r.data;
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async {
    try {
      final r = await _dio.delete(path, data: body);
      return r.data;
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Stream<Uint8List> streamPost(String path,
      {Map<String, dynamic>? body}) async* {
    // 必须先用 base options compose，把实例的 baseUrl（host）拼进请求选项。
    // Dio 的便捷方法（post/get/request）内部都会调 compose(_dio.options, path, ...)，
    // 而 fetch() 本身不会合并 baseUrl。手写 RequestOptions 直接 fetch 会得到
    // 只有相对路径 "/assistant/chat" 的 URI → 报 "no host specified in uri"。
    // 这也是「生成任务」接口独挂、其它接口正常」的根因：只有它走 streamPost。
    final options = Options(
      method: 'POST',
      headers: {'Accept': 'text/event-stream'},
      responseType: ResponseType.stream,
    ).compose(_dio.options, path, data: body);
    // fetch 走拦截器链（Token 注入 + 错误统一）。
    // 注意：非 2xx（含 401 过期 / 5xx / 连接失败）会在 fetch 阶段就抛 DioException，
    // 必须在此处捕获并转 AppException，否则原始 DioException 会逃离本方法，
    // 被上层裸 catch 误报为「网络异常」且丢失真实错误文案。
    final resp = await _safeFetch(options);
    final stream = resp.data?.stream;
    if (stream == null) return;
    try {
      await for (final chunk in stream) {
        yield chunk;
      }
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  /// 统一捕获 fetch 阶段异常：连接/超时/非 2xx 都转成 AppException。
  ///
  /// 原 [streamPost] 直接在正文 `await _dio.fetch`，该调用抛出的 DioException 不在
  /// 内层 try/catch 范围内，会作为原始异常逃离方法，被上层 `catch (e)` 误判为「网络异常」。
  Future<Response<ResponseBody>> _safeFetch(RequestOptions options) async {
    try {
      return await _dio.fetch<ResponseBody>(options);
    } on DioException catch (e) {
      _handleError(e); // Never：统一转 AppException 后抛出
    }
  }
}

/// 统一错误体解析结果。
class _ParsedError {
  final String? code;
  final String message;

  _ParsedError({required this.code, required this.message});
}
