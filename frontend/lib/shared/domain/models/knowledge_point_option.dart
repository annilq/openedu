/// 知识点选择器条目（ADR-0066）：一律来自已上传的教材，所以**必有 id**。
///
/// **为什么在 `shared/` 而不是某个 feature 里**：出题表单（home）、课件（courseware）、
/// 资料库目录（home）三方都要这同一形状。放在任何一个 feature 里，其他 feature 就得
/// 横向 import 它——`feature_boundaries` 的 R2 会拦（courseware → home 就是这么长
/// 出来的），真绕过去就等于开了一条会引发循环依赖的横向通道（后端同规则见 ADR-0027）。
/// 它是**跨 feature 的业务契约**，下沉 shared 是唯一不破分层的位置。
class KnowledgePointOption {
  final String? id;
  final String name;

  /// pending = 待审（可出题可检索、不计掌握度）；curated = 已转正。
  final String status;

  /// emerged = 教材涌现（唯一的来源口径）。
  final String source;

  /// 默认交互式讲解模板（ADR-0061）：[{kind, inputs, controls, ...}]；null = 暂未配置。
  final List<Map<String, dynamic>>? scenes;

  /// 所属学期（ADR-0061 发布任务对接资料库）：'' = 整学年/未分学期；'上学期' / '下学期'。
  /// 「不限学期」查询会并集多个学期，前端据此给知识点加学期后缀标注。
  final String semester;

  const KnowledgePointOption({
    this.id,
    required this.name,
    this.status = 'curated',
    this.source = 'skeleton',
    this.scenes,
    this.semester = '',
  });

  factory KnowledgePointOption.fromJson(Map<String, dynamic> json) =>
      KnowledgePointOption(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? 'curated',
        source: json['source'] as String? ?? 'skeleton',
        scenes: (json['scenes'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        semester: json['semester'] as String? ?? '',
      );
}
