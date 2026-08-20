import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../domain/repositories/auth_repository.dart';

/// 认证状态机：Idle → Loading → Success(user) / Error(message)
sealed class AuthState {
  const AuthState();
}

class AuthIdle extends AuthState {
  const AuthIdle();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthSuccess extends AuthState {
  final UserModel user;
  const AuthSuccess(this.user);
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  AuthNotifier(this._repo) : super(const AuthIdle());

  Future<void> register({
    required String username,
    required String password,
    required String displayName,
  }) async {
    state = const AuthLoading();
    try {
      final result = await _repo.register(
        username: username,
        password: password,
        displayName: displayName,
      );
      state = AuthSuccess(result.user);
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = const AuthLoading();
    try {
      final result = await _repo.login(username: username, password: password);
      state = AuthSuccess(result.user);
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  void reset() => state = const AuthIdle();
}
