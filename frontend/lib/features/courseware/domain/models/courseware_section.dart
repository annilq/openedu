import 'courseware_section_kind.dart';

/// 一个讲解环节（ADR-0067 §3.3）。
///
/// 与后端 `app/features/courseware/schemas.py::CoursewareSection` 逐字段对齐。
///
/// - [script] 是教师话术（「这些图形有什么共同点？」）。按决策 15，它**当提问卡
///   直接投给学生看**——投影时教师屏 = 学生所见，做「仅教师可见」在单屏下物理上
///   不可能，且课堂提问本来就该让学生看见。
/// - [payload] 按 [kind] 释义：
///   - `mediaGallery`: `{items: [{asset_id, caption}]}`
///   - `interactiveScene`: **直接是一份 ADR-0061 SceneSpec**（原样透传渲染器）
///   - `practice`: `{qtype, count}`
class CoursewareSectionModel {
  final String id;
  final CoursewareSectionKind? kind;
  final String title;

  /// 教师话术 / 提问卡文案。
  final String script;

  /// 按 kind 释义的原始 JSON（保持 Map，不做多态建模——渲染交给各自组件）。
  final Map<String, dynamic> payload;

  const CoursewareSectionModel({
    this.id = '',
    this.kind,
    this.title = '',
    this.script = '',
    this.payload = const {},
  });

  factory CoursewareSectionModel.fromJson(Map<String, dynamic> json) =>
      CoursewareSectionModel(
        id: json['id'] as String? ?? '',
        kind: CoursewareSectionKind.tryParse(json['kind'] as String?),
        title: json['title'] as String? ?? '',
        script: json['script'] as String? ?? '',
        payload: json['payload'] is Map
            ? Map<String, dynamic>.from(json['payload'] as Map)
            : const {},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind?.value ?? '',
        'title': title,
        'script': script,
        'payload': payload,
      };

  CoursewareSectionModel copyWith({
    String? id,
    CoursewareSectionKind? kind,
    String? title,
    String? script,
    Map<String, dynamic>? payload,
  }) =>
      CoursewareSectionModel(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        script: script ?? this.script,
        payload: payload ?? this.payload,
      );

  /// 未知 kind（后端新增了类型而前端还没登记）：渲染时给降级提示而不是白屏。
  bool get isUnknownKind => kind == null;
}
