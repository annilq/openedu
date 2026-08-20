/// 环境配置：API Base URL 等。
/// 平板联调时改为电脑局域网 IP，例如 'http://192.168.1.50:8000'。
class AppConfig {
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://127.0.0.1:8000',
  );
  static const String apiPrefix = '/api/v1';
  static String get apiBaseUrl => '$apiBase$apiPrefix';
}
