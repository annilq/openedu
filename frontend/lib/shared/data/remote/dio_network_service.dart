import 'package:dio/dio.dart';

import '../../exceptions/app_exception.dart';
import '../../../configs/app_config.dart';
import '../local/storage_service.dart';
import 'network_service.dart';

/// Dio 网络服务实现。
/// 拦截器 1: Token 注入 — 从 StorageService 取 JWT 放入 Authorization。
/// 拦截器 2: 错误统一 — 非 2xx 转为 HttpException / UnauthorizedException。
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
    final detail = _extractDetail(e.response);
    throw HttpException(detail, statusCode: statusCode);
  }

  String _extractDetail(Response? response) {
    if (response?.data is Map) {
      return response!.data['detail']?.toString() ?? '请求失败 (${response.statusCode})';
    }
    return '请求失败 (${response?.statusCode})';
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
}
