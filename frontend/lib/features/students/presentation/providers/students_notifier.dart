import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';

sealed class ChildrenState {
  const ChildrenState();
}

class ChildrenInitial extends ChildrenState {
  const ChildrenInitial();
}

class ChildrenLoading extends ChildrenState {
  const ChildrenLoading();
}

class StudentsLoaded extends ChildrenState {
  final List<UserModel> students;
  const StudentsLoaded(this.students);
}

class ChildrenError extends ChildrenState {
  final String message;
  const ChildrenError(this.message);
}

class ChildrenNotifier extends StateNotifier<ChildrenState> {
  final StudentsRepository _repo;
  ChildrenNotifier(this._repo) : super(const ChildrenInitial());

  Future<void> loadChildren() async {
    state = const ChildrenLoading();
    try {
      final students = await _repo.getChildren();
      state = StudentsLoaded(students);
    } catch (e) {
      state = ChildrenError(e.toString());
    }
  }

  /// 创建学生；成功返回新用户（并自动刷新列表），失败返回 null（state 置 Error）。
  Future<UserModel?> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
    InterestsModel? interests,
  }) async {
    try {
      final created = await _repo.createChild(
        username: username,
        password: password,
        displayName: displayName,
        grade: grade,
        interests: interests,
      );
      await loadChildren();
      return created;
    } catch (e) {
      state = ChildrenError(e.toString());
      return null;
    }
  }

  /// 编辑学生资料（WF-5）：昵称/年级/兴趣；成功返回更新后的用户并刷新列表，失败返回 null。
  Future<UserModel?> updateChild({
    required String studentId,
    String? displayName,
    int? grade,
    InterestsModel? interests,
  }) async {
    try {
      final updated = await _repo.updateChild(
        studentId: studentId,
        displayName: displayName,
        grade: grade,
        interests: interests,
      );
      await loadChildren();
      return updated;
    } catch (e) {
      state = ChildrenError(e.toString());
      return null;
    }
  }
}
