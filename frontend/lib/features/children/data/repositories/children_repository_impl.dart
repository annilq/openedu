import '../../../../shared/domain/models/models.dart';
import '../../data/datasource/children_remote_data_source.dart';
import '../../domain/repositories/children_repository.dart';

class ChildrenRepositoryImpl implements ChildrenRepository {
  final ChildrenRemoteDataSource _dataSource;
  ChildrenRepositoryImpl(this._dataSource);

  @override
  Future<UserModel> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
  }) async {
    final data = await _dataSource.createChild(
      username: username,
      password: password,
      displayName: displayName,
      grade: grade,
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
}
