import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import '../../../../shared/presentation/resource.dart';

/// 学生管理页状态（ADR-0068 §2.3 / ticket 02）。
///
/// 一次加载聚合三份数据：班级列表（分组头 + 筛选）、按关键词过滤后的学生全量、
/// 各学生活跃错题数。班级筛选的「未分班 / 全部」由页面在取到全量后客户端二次过滤，
/// 不额外打后端。
/// 学生管理页聚合载荷（LCC-08）：班级列表 + 学生列表 + 各学生活跃错题数 + 当前
/// 筛选/搜索，包成 [Resource] 的 `T`。
class StudentManagementData {
  final List<ClassModel> classes;
  final List<UserModel> students;
  final Map<String, int> wrongCounts;
  final String? classId;
  final String keyword;

  const StudentManagementData({
    required this.classes,
    required this.students,
    required this.wrongCounts,
    this.classId,
    this.keyword = '',
  });
}

class StudentManagementNotifier
    extends StateNotifier<Resource<StudentManagementData>>
    with ResourceLoader<StudentManagementData> {
  final StudentsRepository _students;
  final ClassesRepository _classes;

  StudentManagementNotifier(this._students, this._classes)
      : super(const ResourceIdle());

  /// 触发加载。[keyword] 为空串表示不清空旧关键词（保留当前搜索）；
  /// 传 `null` 才显式清空。班级筛选始终走客户端（见类注释）。
  Future<void> load({String? classId, String? keyword}) async {
    final nextKeyword = keyword ?? (state.dataOrNull?.keyword ?? '');
    await runLoad(() async {
      final classes = await _classes.getClasses();
      final students = await _students.getStudents(
        // classId 透传：下钻页（ticket 04）只拉该班学生；全量视图传 null。
        classId: classId,
        keyword: nextKeyword.isEmpty ? null : nextKeyword,
      );
      final counts = await _students.getWrongQuestionCounts();
      return StudentManagementData(
        classes: classes,
        students: students,
        wrongCounts: counts,
        classId: classId,
        keyword: nextKeyword,
      );
    });
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

  /// 批量导入学生（ticket 06）：上传 xlsx，返回逐行结果；成功后重新加载，
  /// 让列表即时反映新增学生。失败抛出由调用方（UI）用 toast 提示。
  Future<StudentImportResultModel> importStudents({
    required List<int> bytes,
    required String filename,
    String? classId,
  }) async {
    final result = await _students.importStudents(
      bytes: bytes,
      filename: filename,
      classId: classId,
    );
    await load();
    return result;
  }

  /// 下载学生导入模板 xlsx（方案A）：拉取字节后交 UI 落盘，不改动列表状态。
  Future<Uint8List> downloadImportTemplate() async {
    return await _students.downloadImportTemplate();
  }
}
