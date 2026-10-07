/// 课件练习经统一助手入口透传的课堂上下文（ADR-0067 §3.6）。
///
/// 这里只描述课件与环节，不表示任务或学生作答；字段均可空以兼容孤儿课件与旧草稿。
///
/// [extra] 是透传透的任意键值（T05 提示级别用 `{'hint_level': 'direction'}`），
/// 由后端 tutor 读取以驱动分级提示；只在非 null 时序列化，避免污染无 extra 的旧调用。
class AssistantCoursewareContext {
  final String? coursewareId;
  final String? sectionId;
  final String? knowledgePoint;
  final String? subject;
  final int? grade;
  final String? semester;
  final Map<String, dynamic>? extra;

  const AssistantCoursewareContext({
    this.coursewareId,
    this.sectionId,
    this.knowledgePoint,
    this.subject,
    this.grade,
    this.semester,
    this.extra,
  });

  AssistantCoursewareContext copyWith({
    String? coursewareId,
    String? sectionId,
    String? knowledgePoint,
    String? subject,
    int? grade,
    String? semester,
    Map<String, dynamic>? extra,
  }) =>
      AssistantCoursewareContext(
        coursewareId: coursewareId ?? this.coursewareId,
        sectionId: sectionId ?? this.sectionId,
        knowledgePoint: knowledgePoint ?? this.knowledgePoint,
        subject: subject ?? this.subject,
        grade: grade ?? this.grade,
        semester: semester ?? this.semester,
        extra: extra ?? this.extra,
      );

  Map<String, dynamic> toJson() => {
    if (coursewareId != null) 'courseware_id': coursewareId,
    if (sectionId != null) 'section_id': sectionId,
    if (knowledgePoint != null) 'knowledge_point': knowledgePoint,
    if (subject != null) 'subject': subject,
    if (grade != null) 'grade': grade,
    if (semester != null) 'semester': semester,
    if (extra != null) 'extra': extra,
  };
}
