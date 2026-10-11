import 'package:kids_learn/shared/domain/models/class_model.dart';

/// 班级仓库抽象（ADR-0036：presentation 只依赖此接口，不认识 datasource）。
abstract class ClassesRepository {
  Future<List<ClassModel>> getClasses();

  /// 新建班级（ADR-0086 班级管理）。
  Future<ClassModel> createClass({required String name, required int grade});

  /// 重命名 / 改年级（ADR-0086）。
  Future<ClassModel> updateClass({
    required String id,
    required String name,
    required int grade,
  });

  /// 删除班级：仅置空班内学生 class_id，不删学生（ADR-0068/0086）。
  Future<void> deleteClass(String id);
}
