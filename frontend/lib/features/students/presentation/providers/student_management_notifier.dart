import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../classes/domain/models/class_model.dart';
import '../../../classes/domain/repositories/classes_repository.dart';
import '../../domain/repositories/students_repository.dart';

/// 学生管理页状态（ADR-0068 §2.3 / ticket 02）。
///
/// 一次加载聚合三份数据：班级列表（分组头 + 筛选）、按关键词过滤后的学生全量、
/// 各学生活跃错题数。班级筛选的「未分班 / 全部」由页面在取到全量后客户端二次过滤，
/// 不额外打后端。
sealed class StudentManagementState {
  const StudentManagementState();
}

class StudentManagementInitial extends StudentManagementState {
  const StudentManagementInitial();
}

class StudentManagementLoading extends StudentManagementState {
  const StudentManagementLoading();
}

class StudentManagementLoaded extends StudentManagementState {
  final List<ClassModel> classes;
  final List<UserModel> students;
  final Map<String, int> wrongCounts;
  final String? classId;
  final String keyword;

  const StudentManagementLoaded({
    required this.classes,
    required this.students,
    required this.wrongCounts,
    this.classId,
    this.keyword = '',
  });
}

class StudentManagementError extends StudentManagementState {
  final String message;
  const StudentManagementError(this.message);
}

class StudentManagementNotifier
    extends StateNotifier<StudentManagementState> {
  final StudentsRepository _students;
  final ClassesRepository _classes;

  StudentManagementNotifier(this._students, this._classes)
      : super(const StudentManagementInitial());

  /// 触发加载。[keyword] 为空串表示不清空旧关键词（保留当前搜索）；
  /// 传 `null` 才显式清空。班级筛选始终走客户端（见类注释）。
  Future<void> load({String? classId, String? keyword}) async {
    final nextKeyword = keyword ??
        (state is StudentManagementLoaded
            ? (state as StudentManagementLoaded).keyword
            : '');
    state = const StudentManagementLoading();
    try {
      final classes = await _classes.getClasses();
      final students = await _students.getStudents(
        keyword: nextKeyword.isEmpty ? null : nextKeyword,
      );
      final counts = await _students.getWrongQuestionCounts();
      state = StudentManagementLoaded(
        classes: classes,
        students: students,
        wrongCounts: counts,
        classId: classId,
        keyword: nextKeyword,
      );
    } catch (e) {
      state = StudentManagementError(e.toString());
    }
  }

  /// 批量移入/移出班级（ticket 03）：[classId] 为 null = 移出归入未分班。
  /// 成功后重新加载，让分组人数即时刷新。失败抛出由调用方（UI）用 toast 提示。
  Future<void> batchReassign({
    required String? classId,
    required List<String> studentIds,
  }) async {
    await _students.batchReassign(classId: classId, studentIds: studentIds);
    await load();
  }
}
