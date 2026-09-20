/// 新增模型请求体。provider 仅允许 ollama / openai_compat。
/// [apiKey] **必填**（ADR-0039，后端同为必填字段）——类型上不给 `null` 的余地。
/// [providerPreset] 为服务商预设 key（如 deepseek），后端据此自动补全
/// provider / base_url；显式传入的 provider / baseUrl 优先。
class ModelCreateReq {
  final String label;
  final String provider;
  final String? baseUrl;
  final String modelName;
  final String apiKey;
  final bool isDefault;
  final String? providerPreset;

  const ModelCreateReq({
    required this.label,
    required this.provider,
    this.baseUrl,
    required this.modelName,
    required this.apiKey,
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

/// 更新模型请求体：`null` 字段 = 不修改。
class ModelUpdateReq {
  final String? label;
  final String? provider;
  final String? baseUrl;
  final String? modelName;
  /// 为 null = **不修改**已有密钥（表单留空即为此意）。ADR-0039 起新增必填，
  /// 但编辑仍允许留空，否则改个名字也得把密钥重打一遍。
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

/// 「测试连接」请求（POST /models/test）：一组**可能还没保存**的模型参数。
///
/// [modelId] 非空时以后台已存配置与加密密钥为底，其余字段只作覆盖——编辑表单
/// 里 API Key 留空（= 不修改）时正是靠它拿库里那份去试。
class ModelProbeReq {
  final String? modelId;
  final String? provider;
  final String? baseUrl;
  final String? modelName;
  final String? apiKey;
  final String? providerPreset;

  const ModelProbeReq({
    this.modelId,
    this.provider,
    this.baseUrl,
    this.modelName,
    this.apiKey,
    this.providerPreset,
  });

  Map<String, dynamic> toJson() => {
        if (modelId != null) 'model_id': modelId,
        if (provider != null) 'provider': provider,
        if (baseUrl != null) 'base_url': baseUrl,
        if (modelName != null) 'model_name': modelName,
        if (apiKey != null && apiKey!.isNotEmpty) 'api_key': apiKey,
        if (providerPreset != null) 'provider_preset': providerPreset,
      };
}
