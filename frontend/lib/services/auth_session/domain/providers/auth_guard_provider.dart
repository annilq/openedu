import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 鉴权失效信号：Dio 层拦截到 401（token 过期/失效）时自增计数，
/// [MyApp] 监听后清登录态并回到登录页。
///
/// 用计数而非 bool：连续多个请求同时 401 时每次自增都能触发监听，
/// 避免首个 401 消费掉 bool 后其余丢失。
final authExpiredProvider =
    StateNotifierProvider<AuthExpiredNotifier, int>((ref) => AuthExpiredNotifier());

class AuthExpiredNotifier extends StateNotifier<int> {
  AuthExpiredNotifier() : super(0);

  /// 通知一次「需要重新登录」。
  void signal() => state++;
}
