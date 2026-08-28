/// 统一异常基类，UI 层捕获后展示友好错误。
class AppException implements Exception {
  final String message;
  final int? statusCode;

  /// 业务/系统错误码（例如 TASK_20001、AUTH_30004）。非错误码流程填充 null。
  final String? code;

  AppException(this.message, {this.statusCode, this.code});

  /// 带错误码前缀的完整展示文案，E-Q3=a 口径。
  String get titledMessage {
    final codePart = (code != null && code!.isNotEmpty) ? '[$code] ' : '';
    return '$codePart$message';
  }

  @override
  String toString() => titledMessage;
}

/// HTTP 网络错误（非 2xx）。
///
/// E-Q2 统一错误体解析：响应体形如 `{code, message, status, data}`。
/// 若响应体缺字段，则退回老 `detail` / 默认文案，保证向后兼容。
class HttpException extends AppException {
  HttpException(
    super.message, {
    super.statusCode,
    super.code,
  });
}

/// 未认证（401），前端应清除 token 并跳登录。
class UnauthorizedException extends AppException {
  UnauthorizedException()
      : super(
          '登录已过期，请重新登录',
          statusCode: 401,
          code: 'AUTH_30001',
        );
}
