/// 资料库只读仓库接口（出题表单的知识点选择器数据源）。
///
/// **为什么接口在 domain、实现在 data**（ADR 分层 R4：`presentation/` 不得 import
/// `*/data/`）：布置任务表单要用 `KnowledgePointOption` 里的 `semester` 给知识点
/// 加学期后缀标注，presentation 直接 import `data/repositories/material_repository_impl.dart`
/// 就是倒挂依赖。选项模型与接口属「业务契约」放domain，实现在 data。
///
/// 教师端资料库的完整管理（上传 / 目录 / 向量化）属 materials feature（B6）；
/// 这里只暴露表单需要的最小面，避免 home 反向依赖一个还没落地的 feature。
library;

/// 知识点选择器条目（ADR-0066）：一律来自已上传的教材，所以**必有 id**。
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

/// 知识点目录响应：条目 + **空目录的原因**。
///
/// [notice] 非空 = 这个范围一条知识点都没有，并说明下一步该做什么（ADR-0051）：
/// 「还没上传过教材」与「有教材但没识别出知识点」是两件不同的事，空列表本身不说
/// 这个区别，教师照着错的提示做就是白跑一趟。
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

/// 知识点选择器的一个可选范围 = **教师真的传过教材**的 (学科, 年级, 学期)（ADR-0065）。
///
/// 后端按教师名下资料聚合出来：没传过教材的学科 / 年级不会出现在列表里——让教师
/// 在 9 年级 × 3 学科里逐个试空门没有意义。
class KnowledgePointScope {
  final String subject;
  final int grade;
  final String semester;

  /// 该范围下的教材份数（下拉里显示出来，印证「这里为什么有知识点」）。
  final int materialCount;

  const KnowledgePointScope({
    required this.subject,
    required this.grade,
    required this.semester,
    this.materialCount = 0,
  });

  factory KnowledgePointScope.fromJson(Map<String, dynamic> json) =>
      KnowledgePointScope(
        subject: json['subject'] as String? ?? '',
        grade: json['grade'] as int? ?? 0,
        semester: json['semester'] as String? ?? '',
        materialCount: json['material_count'] as int? ?? 0,
      );
}

/// 范围清单；[unscopedCount] 是**没识别出学科 / 年级**的教材数（ADR-0065）。
///
/// 这些资料归不到任何范围，UI 必须说出来——教师传了书却在下拉里找不到对应年级，
/// 第一反应会是「上传丢了」。
class KnowledgePointScopeList {
  final List<KnowledgePointScope> scopes;

  /// 学科或年级缺失、归不到任何范围的资料数。
  final int unscopedCount;

  const KnowledgePointScopeList({this.scopes = const [], this.unscopedCount = 0});

  factory KnowledgePointScopeList.fromJson(Map<String, dynamic> json) =>
      KnowledgePointScopeList(
        scopes: (json['scopes'] as List? ?? const [])
            .map((e) =>
                KnowledgePointScope.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        unscopedCount: json['unscoped_count'] as int? ?? 0,
      );
}

abstract class MaterialRepository {
  /// 教师实际上传过教材的知识点范围（ADR-0065）：下拉据此构造，不做全量 9×3 枚举。
  Future<KnowledgePointScopeList> getKnowledgePointScopes();

  Future<KnowledgePointDirectory> getKnowledgePointDirectory({
    required String subject,
    required int grade,
    /// 学期范围维度（ADR-0055 §4 补 / ADR-0061）：
    /// '' = 不限（后端并集该学科该年级**所有**学期）；'上学期' / '下学期' = 精确匹配。
    String semester = '',
  });

  /// 确认（批量转正）知识点：pending→curated。只翻转已有行的状态，不代建条目。
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

  /// 批量删除知识点（多选）。
  ///
  /// 删除只影响目录本身：知识点到题目是快照式引用（题中存的是名字串），所以已出的
  /// 题与掌握度统计不会被破坏——只是这个范围的下拉里不再有它。
  Future<int> deleteKnowledgePoints(List<String> ids);
}
