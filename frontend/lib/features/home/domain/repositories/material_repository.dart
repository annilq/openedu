/// 资料库只读仓库接口（出题表单的知识点选择器数据源）。
///
/// **为什么接口在 domain、实现在 data**（ADR 分层 R4：`presentation/` 不得 import
/// `*/data/`）：布置任务表单要用 `KnowledgePointOption` 里的 `semester` 给知识点
/// 加学期后缀标注，presentation 直接 import `data/repositories/material_repository_impl.dart`
/// 就是倒挂依赖。选项模型与接口属「业务契约」放domain，实现在 data。
///
/// 家长端资料库的完整管理（上传 / 目录 / 向量化）属 materials feature（B6）；
/// 这里只暴露表单需要的最小面，避免 home 反向依赖一个还没落地的 feature。
library;

/// 知识点选择器条目（ADR-0055 §4）：涌现目录（含待审）+ 骨架兜底。
class KnowledgePointOption {
  /// null = 骨架条目（家长确认后才落库获得 id）。
  final String? id;
  final String name;

  /// pending = 待审（可出题可检索、不计掌握度）；curated = 已转正。
  final String status;

  /// emerged = 资料涌现；skeleton = 自编骨架。
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

/// 知识点目录响应（ADR-0061 §L）：条目 + **来源说明**。
///
/// [notice] 非空 = 当前范围没有真实知识点、只剩骨架兜底。骨架是分不出学期的大颗粒
/// 目录，所以那种情况下切学期拿到的下拉会逐字相同——把这句话透到 UI 上，家长才
/// 不会误判成「联动坏了」。
class KnowledgePointDirectory {
  final List<KnowledgePointOption> items;
  final String notice;

  const KnowledgePointDirectory({this.items = const [], this.notice = ''});

  factory KnowledgePointDirectory.fromJson(Map<String, dynamic> json) =>
      KnowledgePointDirectory(
        items: (json['items'] as List? ?? const [])
            .map((e) =>
                KnowledgePointOption.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        notice: json['notice'] as String? ?? '',
      );
}

abstract class MaterialRepository {
  Future<KnowledgePointDirectory> getKnowledgePointDirectory({
    required String subject,
    required int grade,
    /// 学期范围维度（ADR-0055 §4 补 / ADR-0061）：
    /// '' = 不限（后端并集该学科该年级**所有**学期）；'上学期' / '下学期' = 精确匹配。
    String semester = '',
  });

  /// 确认（批量转正）知识点：pending→curated；骨架条目落库为 curated（ADR-0055 §4）。
  Future<void> confirmKnowledgePoints({
    required String subject,
    required int grade,
    required List<String> names,
    String semester = '',
  });

  /// 为知识点编写 / 覆盖默认交互讲解模板（ADR-0061）。空数组 = 清空模板。
  Future<void> updateKnowledgePointScenes({
    required String kpId,
    required List<Map<String, dynamic>> scenes,
  });
}
