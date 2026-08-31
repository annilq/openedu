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
    final parsed = _extractError(e.response);
    throw HttpException(
      parsed.message,
      statusCode: statusCode,
      code: parsed.code,
    );
  }

  _ParsedError _extractError(Response? response) {
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
    return _ParsedError(
      code: code,
      message: '请求失败 (${response?.statusCode ?? '-1'})',
    );
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
  Future<dynamic> delete(String path) async {
    try {
      final r = await _dio.delete(path);
      return r.data;
    } on DioException catch (e) {
      _handleError(e);
    }
  }

  @override
  Stream<Uint8List> streamPost(String path,
      {Map<String, dynamic>? body}) async* {
    final options = RequestOptions(
      path: path,
      method: 'POST',
      data: body,
      headers: {'Accept': 'text/event-stream'},
      responseType: ResponseType.stream,
    );
    // fetch 走拦截器链（Token 注入 + 错误统一），baseUrl 自动拼接。
    final resp = await _dio.fetch<ResponseBody>(options);
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
}

/// 统一错误体解析结果。
class _ParsedError {
  final String? code;
  final String message;

  _ParsedError({required this.code, required this.message});
}
