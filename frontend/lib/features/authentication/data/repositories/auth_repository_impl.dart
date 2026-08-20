import 'dart:convert';

import '../../../../shared/data/local/storage_service.dart';
import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../data/datasource/auth_remote_data_source.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _dataSource;
  final StorageService _storage;

  AuthRepositoryImpl(this._dataSource, this._storage, NetworkService network);

  @override
  Future<({String token, UserModel user})> register({
    required String username,
    required String password,
    required String displayName,
  }) async {
    final data = await _dataSource.register(
      username: username,
      password: password,
      displayName: displayName,
    );
    final token = data['access_token'] as String;
    // Token 响应不含用户信息，先保存 token 再调 /auth/me
    await _storage.saveToken(token);
    final userJson = await _dataSource.me();
    final user = UserModel.fromJson(userJson);
    await _storage.saveUserJson(jsonEncode(user.toJson()));
    return (token: token, user: user);
  }

  @override
  Future<({String token, UserModel user})> login({
    required String username,
    required String password,
  }) async {
    final data = await _dataSource.login(username: username, password: password);
    final token = data['access_token'] as String;
    await _storage.saveToken(token);
    final userJson = await _dataSource.me();
    final user = UserModel.fromJson(userJson);
    await _storage.saveUserJson(jsonEncode(user.toJson()));
    return (token: token, user: user);
  }
}
