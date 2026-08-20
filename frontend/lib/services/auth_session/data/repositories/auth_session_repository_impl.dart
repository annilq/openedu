import 'dart:convert';

import '../../../../shared/data/local/storage_service.dart';
import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../domain/repositories/auth_session_repository.dart';

class AuthSessionRepositoryImpl implements AuthSessionRepository {
  final StorageService _storage;
  final NetworkService _network;

  AuthSessionRepositoryImpl(this._storage, this._network);

  @override
  Future<String?> getToken() => Future.value(_storage.getToken());

  @override
  Future<UserModel?> getCurrentUser() async {
    final json = _storage.getUserJson();
    if (json == null) return null;
    return UserModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  @override
  Future<void> saveSession(String token, UserModel user) async {
    await _storage.saveToken(token);
    await _storage.saveUserJson(jsonEncode(user.toJson()));
  }

  @override
  Future<void> clearSession() => _storage.clearAll();

  @override
  Future<UserModel?> fetchMe() async {
    try {
      final data = await _network.get('/auth/me');
      return UserModel.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
