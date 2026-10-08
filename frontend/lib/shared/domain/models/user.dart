// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

class UserModel {
  final String id;
  final String username;
  final String displayName;
  final String role; // teacher | child
  final int? grade;
  final bool isActive;

  /// 所属班级 ID（ADR-0068）：后端 `UserPublic.class_id` 增量字段，未分班为 null。
  /// 学生管理页按它分组，班级实体本身由 classes feature 取数。
  final String? classId;

  UserModel({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    this.grade,
    this.isActive = true,
    this.classId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      role: json['role'] as String,
      grade: json['grade'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      classId: json['class_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'role': role,
        'grade': grade,
        'is_active': isActive,
        'class_id': classId,
      };

  bool get isTeacher => role == 'teacher';
}
