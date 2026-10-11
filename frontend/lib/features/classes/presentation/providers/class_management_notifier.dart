import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kids_learn/shared/domain/models/class_model.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';

/// 班级管理页状态（ADR-0086）。
///
/// 一次加载班级列表；增 / 改 / 删成功后重新加载，让卡片与人数即时刷新。
sealed class ClassManagementState {
  const ClassManagementState();
}

class ClassManagementInitial extends ClassManagementState {
  const ClassManagementInitial();
}

class ClassManagementLoading extends ClassManagementState {
  const ClassManagementLoading();
}

class ClassManagementLoaded extends ClassManagementState {
  final List<ClassModel> classes;
  const ClassManagementLoaded(this.classes);
}

class ClassManagementError extends ClassManagementState {
  final String message;
  const ClassManagementError(this.message);
}

class ClassManagementNotifier
    extends StateNotifier<ClassManagementState> {
  final ClassesRepository _repo;

  ClassManagementNotifier(this._repo) : super(const ClassManagementInitial());

  Future<void> load() async {
    state = const ClassManagementLoading();
    try {
      final classes = await _repo.getClasses();
      state = ClassManagementLoaded(classes);
    } catch (e) {
      state = ClassManagementError(e.toString());
    }
  }

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
