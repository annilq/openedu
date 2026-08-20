import '../../../../shared/data/remote/network_service.dart';

/// 认证远程数据源：纯网络调用，不关心存储。
class AuthRemoteDataSource {
  final NetworkService _network;
  AuthRemoteDataSource(this._network);

  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String displayName,
  }) async {
    return await _network.post('/auth/register', body: {
      'username': username,
      'password': password,
      'display_name': displayName,
    });
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    return await _network.post('/auth/login', body: {
      'username': username,
      'password': password,
    });
  }

  Future<Map<String, dynamic>> me() async {
    return await _network.get('/auth/me');
  }
}
