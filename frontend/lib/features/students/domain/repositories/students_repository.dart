import '../../../../shared/domain/models/models.dart';

abstract class StudentsRepository {
  Future<UserModel> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
    InterestsModel? interests,
  });
  Future<UserModel> updateChild({
    required String studentId,
    String? displayName,
    int? grade,
    InterestsModel? interests,
  });
  Future<List<UserModel>> getChildren();
}
