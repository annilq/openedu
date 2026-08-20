import '../../../../shared/domain/models/models.dart';

abstract class ChildrenRepository {
  Future<UserModel> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
  });
  Future<List<UserModel>> getChildren();
}
