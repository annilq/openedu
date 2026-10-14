import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../../../shared/exceptions/app_exception.dart';
import '../../domain/model_requests.dart';
import '../../domain/repositories/models_repository.dart';
import '../../providers/models_provider.dart';
import '../../../../shared/presentation/resource.dart';

/// 模型管理页聚合载荷（LCC-08）：自定义模型列表 + 供应商预设，包成 [Resource] 的 `T`。
class ModelsData {
  final ModelListResp resp;
  final List<ModelProviderPreset> providers;
  const ModelsData(this.resp, this.providers);
}

/// 模型管理加载态统一为 [Resource]：带写动作（增/改/删/设默认后重载），故
/// `with ResourceLoader` 复用四态落法（LCC-08）。
class ModelsNotifier extends StateNotifier<Resource<ModelsData>>
    with ResourceLoader<ModelsData> {
  final ModelsRepository _repo;
  ModelsNotifier(this._repo) : super(const ResourceIdle());

  Future<void> load() => runLoad(() async {
        final resp = await _repo.list();
        final providers = await _repo.providers();
        return ModelsData(resp, providers);
      });

  /// 新增自定义模型；成功后刷新列表。返回 null 表示成功。
  Future<String?> create(ModelCreateReq req) async {
    try {
      await _repo.create(req);
      await load();
      return null;
    } on AppException catch (e) {
      return e.message;
    } catch (e) {
      return '添加失败，请稍后重试';
    }
  }

  /// 更新自定义模型；成功后刷新列表。返回 null 表示成功。
  Future<String?> update(String id, ModelUpdateReq req) async {
    try {
      await _repo.update(id, req);
      await load();
      return null;
    } on AppException catch (e) {
      return e.message;
    } catch (e) {
      return '保存失败，请稍后重试';
    }
  }

  /// 删除自定义模型；成功后刷新列表。返回 null 表示成功。
  Future<String?> delete(String id) async {
    try {
      await _repo.delete(id);
      await load();
      return null;
    } on AppException catch (e) {
      return e.message;
    } catch (e) {
      return '删除失败，请稍后重试';
    }
  }

  /// 「测试连接」：拿一组（可能尚未保存的）参数去后端真发一次请求。
  ///
  /// **不抛异常**：连不上是本功能要回答的正常结论之一（后端 200 + `ok=false`），
  /// 故一律包成 [ModelProbeResult] 交 UI 渲染；只有网络层/鉴权类异常才在此兜底。
  Future<ModelProbeResult> testConnection(ModelProbeReq req) async {
    try {
      return await _repo.testConnection(req);
    } on AppException catch (e) {
      return ModelProbeResult(
          ok: false, latencyMs: 0, message: e.message, errorKind: 'client');
    } catch (e) {
      return ModelProbeResult(
          ok: false,
          latencyMs: 0,
          message: '测试失败：${e.toString()}',
          errorKind: 'client');
    }
  }

  /// 设为默认模型；成功后刷新列表。返回 null 表示成功。
  Future<String?> setDefault(String id) async {
    try {
      await _repo.setDefault(id);
      await load();
      return null;
    } on AppException catch (e) {
      return e.message;
    } catch (e) {
      return '设置默认失败，请稍后重试';
    }
  }
}

final modelsNotifierProvider =
    StateNotifierProvider<ModelsNotifier, Resource<ModelsData>>((ref) {
  return ModelsNotifier(ref.watch(modelsRepositoryProvider));
});
