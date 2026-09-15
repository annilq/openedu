import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../../../shared/exceptions/app_exception.dart';
import '../../domain/model_requests.dart';
import '../../domain/repositories/models_repository.dart';
import '../../providers/models_provider.dart';

sealed class ModelsState {
  const ModelsState();
}

class ModelsInitial extends ModelsState {
  const ModelsInitial();
}

class ModelsLoading extends ModelsState {
  const ModelsLoading();
}

class ModelsLoaded extends ModelsState {
  final ModelListResp resp;
  final List<ModelProviderPreset> providers;
  const ModelsLoaded(this.resp, this.providers);
}

class ModelsError extends ModelsState {
  final String message;
  const ModelsError(this.message);
}

class ModelsNotifier extends StateNotifier<ModelsState> {
  final ModelsRepository _repo;
  ModelsNotifier(this._repo) : super(const ModelsInitial());

  Future<void> load() async {
    if (state is! ModelsLoading) state = const ModelsLoading();
    try {
      final resp = await _repo.list();
      final providers = await _repo.providers();
      state = ModelsLoaded(resp, providers);
    } catch (e) {
      state = ModelsError(e.toString());
    }
  }

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
    StateNotifierProvider<ModelsNotifier, ModelsState>((ref) {
  return ModelsNotifier(ref.watch(modelsRepositoryProvider));
});
