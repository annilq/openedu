import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/presentation/resource.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';

// 学生端：本教师全部学生列表（LCC-08）。
//
// 取一次就显示；createChild / updateChild 成功后重载整列表（返回新用户给调用方）。
// 带写动作且需回传值，故用自定义 notifier `with ResourceLoader`，保留 _repo 与
// 写方法；四态落法下沉到 ResourceLoader.runLoad，不再手写 sealed 四态类。
class ChildrenNotifier
    extends StateNotifier<Resource<List<UserModel>>>
    with ResourceLoader<List<UserModel>> {
  final StudentsRepository _repo;
  ChildrenNotifier(this._repo) : super(const ResourceIdle());

  Future<void> loadChildren() => runLoad(_repo.getChildren);

  /// 创建学生；成功返回新用户（并自动刷新列表），失败返回 null（state 置 Error）。
  Future<UserModel?> createChild({
    required String username,
    required String password,
    required String displayName,
    String? classId,
  }) async {
    try {
      final created = await _repo.createChild(
        username: username,
        password: password,
        displayName: displayName,
        classId: classId,
      );
      await loadChildren();
      return created;
    } catch (e) {
      state = ResourceError<List<UserModel>>(e.toString());
      return null;
    }
  }

  /// 编辑学生资料（WF-5）：仅昵称可改（年级已改由班级承载，ADR-0086 修正）；
  /// 成功返回更新后的用户并刷新列表，失败返回 null。
  Future<UserModel?> updateChild({
    required String studentId,
    String? displayName,
  }) async {
    try {
      final updated = await _repo.updateChild(
        studentId: studentId,
        displayName: displayName,
      );
      await loadChildren();
      return updated;
    } catch (e) {
      state = ResourceError<List<UserModel>>(e.toString());
      return null;
    }
  }
}
