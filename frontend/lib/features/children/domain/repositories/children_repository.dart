import '../../../../shared/domain/models/models.dart';

abstract class ChildrenRepository {
  Future<UserModel> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
    InterestsModel? interests,
  });
  Future<UserModel> updateChild({
    required String childId,
    String? displayName,
    int? grade,
    InterestsModel? interests,
  });
  Future<List<UserModel>> getChildren();
}
