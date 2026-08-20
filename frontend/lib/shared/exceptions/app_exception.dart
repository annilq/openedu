/// 统一异常基类，UI 层捕获后展示友好错误。
class AppException implements Exception {
  final String message;
  final int? statusCode;

  AppException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// HTTP 网络错误（非 2xx）。
class HttpException extends AppException {
  HttpException(super.message, {super.statusCode});
}

/// 未认证（401），前端应清除 token 并跳登录。
class UnauthorizedException extends AppException {
  UnauthorizedException() : super('登录已过期，请重新登录', statusCode: 401);
}
