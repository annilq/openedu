/// 课件环节类型（ADR-0067 §3.3 注册表）。
///
/// ⚠️ courseware-round-3 T03（去 kind·expand）起，环节不再按 kind 类型化——每个
/// 环节是统一的「内容块容器」，渲染 / 编辑都「按填了什么」（materials / scene /
/// practice / 话术）。本枚举退化为**可选只读的旧数据兼容字段**：
///
/// - 旧课件带 kind 时仍用它做兜底展示标签；
/// - 新数据可不带 kind，新建 / 起草都不再产出 kind；
/// - 删除本枚举与 `kind` 字段归 T07 contract。
///
/// ⚠️ 这是**环节**类型，与 ADR-0061 的 SceneSpec 渲染器 kind（`reflection` /
/// `bar_chart`…）是两层。`interactiveScene` 在两层同名不同义：
/// 这里表示「这一环节是交互演示」，SceneSpec 层表示「用哪个渲染器」。
/// 两套枚举各自登记、禁止互相映射复用。
@Deprecated('courseware-round-3 T03 起环节去 kind：渲染按内容块，kind 仅作旧数据兼容')
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

/// 环节类型的中文标签（仅作旧数据展示兜底，T03 后编辑器不再用 kind 选择器）。
@Deprecated('courseware-round-3 T03 起环节去 kind，标签仅旧数据展示兜底')
const kCoursewareSectionKindLabels = <CoursewareSectionKind, String>{
  CoursewareSectionKind.mediaGallery: '素材展示',
  CoursewareSectionKind.interactiveScene: '交互讲解',
  CoursewareSectionKind.practice: '课堂练习',
};
