import '../../data/datasource/classes_remote_data_source.dart';
import 'package:kids_learn/shared/domain/models/class_model.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';

class ClassesRepositoryImpl implements ClassesRepository {
  final ClassesRemoteDataSource _dataSource;
  ClassesRepositoryImpl(this._dataSource);

  @override
  Future<List<ClassModel>> getClasses() async {
    final list = await _dataSource.getClasses();
    return list
        .map((e) => ClassModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
