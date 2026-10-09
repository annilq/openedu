import 'dart:typed_data';

import 'package:kids_learn/shared/domain/models/models.dart';

abstract class StudentsRepository {
  Future<UserModel> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
  });
  Future<UserModel> updateChild({
    required String studentId,
    String? displayName,
    int? grade,
  });
  Future<List<UserModel>> getChildren();

  /// 学生管理页取数：叠加班级筛选与姓名/学号搜索（见 datasource 注释）。
  Future<List<UserModel>> getStudents({
    String? classId,
    String? keyword,
  });

  /// 各学生活跃错题数（{student_id: count}）。
  Future<Map<String, int>> getWrongQuestionCounts();

  /// 批量移入/移出班级（ticket 03）。[classId] 为 null = 移出归入未分班。
  Future<void> batchReassign({
    required String? classId,
    required List<String> studentIds,
  });

  /// 批量导入学生（ticket 06）：上传 xlsx，返回逐行结果。
  Future<StudentImportResultModel> importStudents({
    required List<int> bytes,
    required String filename,
  });

  /// 下载学生导入模板 xlsx（方案A）：表头与导入解析口径一致（姓名 / 学号）。
  Future<Uint8List> downloadImportTemplate();
}
