import 'package:kids_learn/shared/domain/models/class_model.dart';

/// 班级仓库抽象（ADR-0036：presentation 只依赖此接口，不认识 datasource）。
abstract class ClassesRepository {
  Future<List<ClassModel>> getClasses();
}
