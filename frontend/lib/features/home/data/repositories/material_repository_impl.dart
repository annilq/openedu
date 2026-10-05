import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/utils/json_decode.dart';
import '../../domain/repositories/material_repository.dart';

/// 资料库仓库实现：端点拼装与 JSON 解析在此，业务契约（接口 + 选项模型）
/// 在 `domain/repositories/material_repository.dart`——这样布置任务表单能用
/// `KnowledgePointOption.semester` 而不必 import `data/`（ADR 分层 R4）。
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
