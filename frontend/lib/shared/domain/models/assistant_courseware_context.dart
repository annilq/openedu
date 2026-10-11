/// 课件经统一助手入口透传的课堂上下文（ADR-0067 §3.6，ADR-0072）。
///
/// 这里只描述课件与环节，不表示任务或学生作答；字段均可空以兼容孤儿课件与旧草稿。
class AssistantCoursewareContext {
  final String? coursewareId;
  final String? knowledgePoint;
  // ADR-0072：知识点精确 id（无同名漂移）。优先于 [knowledgePoint] name 口径；
  // 缺失时后端回落 name。仅在非空时下发。
  final String? knowledgePointId;
  final String? subject;
  final int? grade;
  final String? semester;

  const AssistantCoursewareContext({
    this.coursewareId,
    this.knowledgePoint,
    this.knowledgePointId,
    this.subject,
    this.grade,
    this.semester,
  });

  AssistantCoursewareContext copyWith({
    String? coursewareId,
    String? knowledgePoint,
    String? knowledgePointId,
    String? subject,
    int? grade,
    String? semester,
  }) =>
      AssistantCoursewareContext(
        coursewareId: coursewareId ?? this.coursewareId,
        knowledgePoint: knowledgePoint ?? this.knowledgePoint,
        knowledgePointId: knowledgePointId ?? this.knowledgePointId,
        subject: subject ?? this.subject,
        grade: grade ?? this.grade,
        semester: semester ?? this.semester,
      );

  Map<String, dynamic> toJson() => {
        if (coursewareId != null) 'courseware_id': coursewareId,
        if (knowledgePoint != null) 'knowledge_point': knowledgePoint,
        if (knowledgePointId != null) 'knowledge_point_id': knowledgePointId,
        if (subject != null) 'subject': subject,
        if (grade != null) 'grade': grade,
        if (semester != null) 'semester': semester,
      };
}
