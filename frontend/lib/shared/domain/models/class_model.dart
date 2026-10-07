/// 班级领域模型（ADR-0068）：与后端 `ClassResp` 对齐。
///
/// [studentCount] 由后端 `GET /classes` 一并聚合返回，前端筛选下拉可直接显示人数，
/// 不必再二次请求。分组展示时也是「X班 (n人)」的来源。
class ClassModel {
  final String id;
  final String name;
  final int grade;
  final int studentCount;

  const ClassModel({
    required this.id,
    required this.name,
    required this.grade,
    this.studentCount = 0,
  });

  factory ClassModel.fromJson(Map<String, dynamic> json) => ClassModel(
        id: json['id'] as String,
        name: json['name'] as String,
        grade: json['grade'] as int,
        studentCount: (json['student_count'] as int?) ?? 0,
      );
}
