import 'courseware_section.dart';

/// 一份课件 = 一个知识点上的一串讲解环节（ADR-0067 §3.2）。
///
/// 与后端 `app/features/courseware/schemas.py::CoursewareResp` 逐字段对齐。
///
/// 课件是 `KnowledgePoint.scenes` 的**上位容器**：scenes 是「一个知识点 → 一份
/// 交互场景模板」，课件是「一个知识点 → 一串有序、类型各异的环节」。
class CoursewareModel {
  final String id;
  final String? subject;
  final int? grade;
  final String? semester;
  final String? knowledgePointId;

  /// 知识点名快照：知识点被 ADR-0064 清理后课件仍可读（§4.1）。
  final String kpName;
  final String title;

  /// `draft` = 还在调；`ready` = 可以直接上讲台。**不阻塞演示**——它只是列表标签。
  final String status;
  final List<CoursewareSectionModel> sections;

  /// 教学目标 / 备课依据（courseware-round-3 T01）：空壳课件建出时存教师填的内容，
  /// 「AI 补充讲解」（T05）会读它当起草上下文。可空。
  final String? objective;

  /// 所属知识点已被清理（孤儿课件）：列表据此标注，课件仍可用。
  final bool kpMissing;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CoursewareModel({
    this.id = '',
    this.subject,
    this.grade,
    this.semester,
    this.knowledgePointId,
    this.kpName = '',
    this.title = '',
    this.status = 'draft',
    this.sections = const [],
    this.objective,
    this.kpMissing = false,
    this.createdAt,
    this.updatedAt,
  });

  factory CoursewareModel.fromJson(Map<String, dynamic> json) => CoursewareModel(
        id: json['id'] as String? ?? '',
        subject: json['subject'] as String?,
        grade: json['grade'] as int?,
        semester: json['semester'] as String?,
        knowledgePointId: json['knowledge_point_id'] as String?,
        kpName: json['kp_name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        status: json['status'] as String? ?? 'draft',
        sections: (json['sections'] as List? ?? const [])
            .map((e) =>
                CoursewareSectionModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        kpMissing: json['kp_missing'] as bool? ?? false,
        objective: json['objective'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      );

  /// 展示名：优先课件标题，空则回落知识点名快照。
  String get displayTitle => title.isEmpty ? kpName : title;

  bool get isReady => status == 'ready';

  bool get isEmpty => sections.isEmpty;
}
