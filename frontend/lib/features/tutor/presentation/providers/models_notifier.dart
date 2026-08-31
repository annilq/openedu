import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../../../shared/exceptions/app_exception.dart';

// ───────── AI 模型管理（票据 08，仅家长） ─────────
/// 新增 / 更新模型请求体。provider 仅允许 ollama / openai_compat。
/// [providerPreset] 为内置服务商预设 key（如 deepseek），后端据此自动补全
/// provider / base_url；显式传入的 provider / baseUrl 优先。
class ModelCreateReq {
  final String label;
  final String provider;
  final String? baseUrl;
  final String modelName;
  final String? apiKey;
  final bool isDefault;
  final String? providerPreset;

  const ModelCreateReq({
    required this.label,
    required this.provider,
    this.baseUrl,
    required this.modelName,
    this.apiKey,
    this.isDefault = false,
    this.providerPreset,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'provider': provider,
        'base_url': baseUrl,
        'model_name': modelName,
        'api_key': apiKey,
        'is_default': isDefault,
        if (providerPreset != null) 'provider_preset': providerPreset,
      };
}

class ModelUpdateReq {
  final String? label;
  final String? provider;
  final String? baseUrl;
  final String? modelName;
  final String? apiKey;
  final bool? isDefault;
  final String? providerPreset;

  const ModelUpdateReq({
    this.label,
    this.provider,
    this.baseUrl,
    this.modelName,
    this.apiKey,
    this.isDefault,
    this.providerPreset,
  });

  Map<String, dynamic> toJson() => {
        if (label != null) 'label': label,
        if (provider != null) 'provider': provider,
        if (baseUrl != null) 'base_url': baseUrl,
        if (modelName != null) 'model_name': modelName,
        if (apiKey != null) 'api_key': apiKey,
        if (isDefault != null) 'is_default': isDefault,
        if (providerPreset != null) 'provider_preset': providerPreset,
      };
}

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
  final NetworkService _network;
  ModelsNotifier(this._network) : super(const ModelsInitial());

  Future<void> load() async {
    if (state is! ModelsLoading) state = const ModelsLoading();
    try {
      final results = await Future.wait([
        _network.get('/models'),
        _network.get('/models/providers'),
      ]);
      final resp = ModelListResp.fromJson(results[0] as Map<String, dynamic>);
      final providers = (results[1] as List)
          .map((e) => ModelProviderPreset.fromJson(e as Map<String, dynamic>))
          .toList();
      state = ModelsLoaded(resp, providers);
    } catch (e) {
      state = ModelsError(e.toString());
    }
  }

  /// 新增自定义模型；成功后刷新列表。返回 null 表示成功。
  Future<String?> create(ModelCreateReq req) async {
    try {
      await _network.post('/models', body: req.toJson());
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
      await _network.put('/models/$id', body: req.toJson());
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
      await _network.delete('/models/$id');
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
      await _network.put('/models/default', body: {'id': id});
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
  final network = ref.watch(networkServiceProvider);
  return ModelsNotifier(network);
});
