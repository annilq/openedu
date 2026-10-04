import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/utils/json_decode.dart';

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

  const KnowledgePointOption({
    this.id,
    required this.name,
    this.status = 'curated',
    this.source = 'skeleton',
    this.scenes,
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
      );
}

/// 资料库只读仓库：出题表单的知识点选择器数据源。
///
/// 家长端资料库的完整管理（上传 / 目录 / 向量化）属 materials feature（B6）；
/// 这里只暴露表单需要的最小面，避免 home 反向依赖一个还没落地的 feature。
abstract class MaterialRepository {
  Future<List<KnowledgePointOption>> getKnowledgePoints({
    required String subject,
    required int grade,
    /// 学期范围维度（ADR-0055 §4 补）：'' = 整学年/不限；'上学期' / '下学期'。
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

class MaterialRepositoryImpl implements MaterialRepository {
  MaterialRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<List<KnowledgePointOption>> getKnowledgePoints({
    required String subject,
    required int grade,
    String semester = '',
  }) async {
    final data = await _network.get(
      '/materials/knowledge-points',
      query: {'subject': subject, 'grade': grade, 'semester': semester},
    );
    final items = decodeMap(data)['items'] as List? ?? const [];
    return items
        .map((e) => KnowledgePointOption.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> confirmKnowledgePoints({
    required String subject,
    required int grade,
    required List<String> names,
    String semester = '',
  }) async {
    await _network.post(
      '/materials/knowledge-points/confirm',
      body: {'names': names, 'subject': subject, 'grade': grade, 'semester': semester},
    );
  }

  @override
  Future<void> updateKnowledgePointScenes({
    required String kpId,
    required List<Map<String, dynamic>> scenes,
  }) async {
    await _network.patch(
      '/materials/knowledge-points/$kpId/scenes',
      body: {'scenes': scenes},
    );
  }
}
