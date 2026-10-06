/// 课件练习经统一助手入口透传的课堂上下文（ADR-0067 §3.6）。
///
/// 这里只描述课件与环节，不表示任务或学生作答；字段均可空以兼容孤儿课件与旧草稿。
class AssistantCoursewareContext {
  final String? coursewareId;
  final String? sectionId;
  final String? knowledgePoint;
  final String? subject;
  final int? grade;
  final String? semester;

  const AssistantCoursewareContext({
    this.coursewareId,
    this.sectionId,
    this.knowledgePoint,
    this.subject,
    this.grade,
    this.semester,
  });

  Map<String, dynamic> toJson() => {
    if (coursewareId != null) 'courseware_id': coursewareId,
    if (sectionId != null) 'section_id': sectionId,
    if (knowledgePoint != null) 'knowledge_point': knowledgePoint,
    if (subject != null) 'subject': subject,
    if (grade != null) 'grade': grade,
    if (semester != null) 'semester': semester,
  };
}
