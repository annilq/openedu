// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

/// 娃娃兴趣画像（WF-1 定稿）：受控分类叶子 key 列表 + 「其他爱好」自由文本（≤50 字）。
/// 与后端 `User.interests` 的 {categories, free_text} 形态对齐。
class InterestsModel {
  final List<String> categories; // 受控分类叶子 key（含二级，如 "恐龙"）
  final String? freeText; // 「其他爱好」自由文本

  InterestsModel({this.categories = const [], this.freeText});

  factory InterestsModel.fromJson(Map<String, dynamic> json) {
    final cats = (json['categories'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    return InterestsModel(
      categories: cats,
      freeText: json['free_text'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'categories': categories,
        'free_text': freeText,
      };

  /// 全空（无分类、无自由文本）视为未设置。
  bool get isEmpty =>
      categories.isEmpty && (freeText == null || freeText!.isEmpty);
}

class UserModel {
  final String id;
  final String username;
  final String displayName;
  final String role; // parent | child
  final int? grade;
  final bool isActive;
  final InterestsModel? interests; // 兴趣画像（WF-1/WF-2）

  UserModel({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    this.grade,
    this.isActive = true,
    this.interests,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      role: json['role'] as String,
      grade: json['grade'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      interests: json['interests'] == null
          ? null
          : InterestsModel.fromJson(
              json['interests'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'role': role,
    'grade': grade,
    'is_active': isActive,
    'interests': interests?.toJson(),
  };

  bool get isParent => role == 'parent';
}
