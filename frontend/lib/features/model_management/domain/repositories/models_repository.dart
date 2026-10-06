import '../models.dart';
import '../model_requests.dart';

/// AI 模型管理（仅教师）：无内置模型目录，全靠教师手填（ADR-0039）。
abstract class ModelsRepository {
  Future<ModelListResp> list();
  Future<List<ModelProviderPreset>> providers();
  Future<void> create(ModelCreateReq req);
  Future<void> update(String id, ModelUpdateReq req);
  Future<void> delete(String id);
  Future<void> setDefault(String id);
  Future<ModelProbeResult> testConnection(ModelProbeReq req);
}
