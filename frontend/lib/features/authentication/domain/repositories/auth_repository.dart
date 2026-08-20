import '../../../../shared/domain/models/models.dart';

abstract class AuthRepository {
  Future<({String token, UserModel user})> register({
    required String username,
    required String password,
    required String displayName,
  });
  Future<({String token, UserModel user})> login({
    required String username,
    required String password,
  });
}
