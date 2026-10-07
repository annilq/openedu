import '../../../../shared/domain/models/models.dart';
import '../../data/datasource/students_remote_data_source.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';

class StudentsRepositoryImpl implements StudentsRepository {
  final StudentsRemoteDataSource _dataSource;
  StudentsRepositoryImpl(this._dataSource);

  @override
  Future<UserModel> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
    InterestsModel? interests,
  }) async {
    final data = await _dataSource.createChild(
      username: username,
      password: password,
      displayName: displayName,
      grade: grade,
      interests: interests?.isEmpty ?? true ? null : interests!.toJson(),
    );
    return UserModel.fromJson(data);
  }

  @override
  Future<UserModel> updateChild({
    required String studentId,
    String? displayName,
    int? grade,
    InterestsModel? interests,
  }) async {
    final data = await _dataSource.updateChild(
      studentId: studentId,
      displayName: displayName,
      grade: grade,
      interests: interests?.isEmpty ?? true ? null : interests!.toJson(),
    );
    return UserModel.fromJson(data);
  }

  @override
  Future<List<UserModel>> getChildren() async {
    final list = await _dataSource.getChildren();
    return list
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<UserModel>> getStudents({
    String? classId,
    String? keyword,
  }) async {
    final list = await _dataSource.getStudents(
      classId: classId,
      keyword: keyword,
    );
    return list
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Map<String, int>> getWrongQuestionCounts() async {
    return await _dataSource.getWrongQuestionCounts();
  }

  @override
  Future<void> batchReassign({
    required String? classId,
    required List<String> studentIds,
  }) async {
    await _dataSource.batchReassign(
      classId: classId,
      studentIds: studentIds,
    );
  }

  @override
  Future<StudentImportResultModel> importStudents({
    required List<int> bytes,
    required String filename,
  }) async {
    final data =
        await _dataSource.importStudents(bytes: bytes, filename: filename);
    return StudentImportResultModel.fromJson(data);
  }
}
