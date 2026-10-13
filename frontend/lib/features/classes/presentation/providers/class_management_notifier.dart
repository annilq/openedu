import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kids_learn/shared/domain/models/class_model.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/shared/presentation/resource.dart';

/// 班级管理页状态（ADR-0086）。
///
/// 一次加载班级列表；增 / 改 / 删成功后重新加载，让卡片与人数即时刷新。
/// 加载态统一用共享的 [Resource<T>]（LCC-08）：Idle/Loading → 骨架占位，Error → 重试，
/// Loaded → 列表。取数逻辑下沉到 [ResourceLoader._run]，不再手写 4 态 sealed 类；
/// 本页带写动作（create/update/delete 后重载），故自定义 notifier `with ResourceLoader`
/// 而非用现成的只读 [ResourceNotifier]。
class ClassManagementNotifier
    extends StateNotifier<Resource<List<ClassModel>>>
    with ResourceLoader<List<ClassModel>> {
  final ClassesRepository _repo;

  ClassManagementNotifier(this._repo) : super(const ResourceIdle());

  Future<void> load() => runLoad(_repo.getClasses);

  Future<void> createClass({
    required String name,
    required int grade,
  }) async {
    await _repo.createClass(name: name, grade: grade);
    await load();
  }

  Future<void> updateClass({
    required String id,
    required String name,
    required int grade,
  }) async {
    await _repo.updateClass(id: id, name: name, grade: grade);
    await load();
  }

  Future<void> deleteClass(String id) async {
    await _repo.deleteClass(id);
    await load();
  }
}
