/// 课件环节类型（ADR-0067 §3.3 注册表）。
///
/// ⚠️ 这是**环节**类型，与 ADR-0061 的 SceneSpec 渲染器 kind（`reflection` /
/// `bar_chart`…）是两层。`interactiveScene` 在两层同名不同义：
/// 这里表示「这一环节是交互演示」，SceneSpec 层表示「用哪个渲染器」。
/// 两套枚举各自登记、禁止互相映射复用。
enum CoursewareSectionKind {
  /// 生活素材 / 欣赏（环节 1、3）：图片画廊。
  mediaGallery('media_gallery'),

  /// 交互判定（环节 2）：payload 直接是一份 ADR-0061 SceneSpec。
  interactiveScene('interactive_scene'),

  /// 课堂练习（环节 4）：AI 出题 + 教师代录对错。
  practice('practice');

  const CoursewareSectionKind(this.value);

  /// 后端注册表里的字符串（落库与传输用）。
  final String value;

  static CoursewareSectionKind? tryParse(String? raw) {
    for (final k in CoursewareSectionKind.values) {
      if (k.value == raw) return k;
    }
    return null;
  }
}

/// 环节类型的中文标签（编辑页 kind 选择器用）。
const kCoursewareSectionKindLabels = <CoursewareSectionKind, String>{
  CoursewareSectionKind.mediaGallery: '素材展示',
  CoursewareSectionKind.interactiveScene: '交互讲解',
  CoursewareSectionKind.practice: '课堂练习',
};
