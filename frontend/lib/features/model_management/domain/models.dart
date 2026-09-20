// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

/// `features/model_management` 独占的领域模型：AI 模型配置与服务商预设。
///
/// 从 `shared/domain/models/models.dart` 拆出——只在模型管理页与模型仓库中使用，
/// 无内置模型目录（ADR-0039），这些类也不该被其它 feature 引用。
// ───────── AI 模型（票据 08 多模型流式） ─────────
/// 内置服务商预设（GET /models/providers）：用于「添加模型」时自动带出
/// base_url 与模型名建议，简化家长手动输入。
library;
class ModelProviderPreset {
  final String key; // deepseek / openai / ollama ...
  final String label;
  final String provider; // ollama | openai_compat
  final String? baseUrl;
  final List<String> models; // 该服务商常见模型名建议
  final String? apiKeyHint;
  final String? docUrl;

  const ModelProviderPreset({
    required this.key,
    required this.label,
    required this.provider,
    this.baseUrl,
    this.models = const [],
    this.apiKeyHint,
    this.docUrl,
  });

  factory ModelProviderPreset.fromJson(Map<String, dynamic> json) {
    return ModelProviderPreset(
      key: json['key'] as String,
      label: json['label'] as String,
      provider: json['provider'] as String,
      baseUrl: json['base_url'] as String?,
      models: (json['models'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      apiKeyHint: json['api_key_hint'] as String?,
      docUrl: json['doc_url'] as String?,
    );
  }
}

/// 单个可选模型（ADR-0039：模型一律由家长手动录入，不再区分内置/自定义）。
class ModelInfo {
  final String id;
  final String label;
  final String provider; // ollama | openai_compat
  final String? baseUrl;
  final String modelName;
  final bool isDefault;

  const ModelInfo({
    required this.id,
    required this.label,
    required this.provider,
    this.baseUrl,
    required this.modelName,
    this.isDefault = false,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'].toString(),
      label: json['label'] as String,
      provider: json['provider'] as String,
      baseUrl: json['base_url'] as String?,
      modelName: json['model_name'] as String,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}

/// 「测试连接」结果（POST /models/test）。
///
/// 注意**测不通也是 200**：后端把「连不上」当作要回答的正常结论之一（`ok=false`），
/// 只有参数不合法 / 模型不属于你才走 4xx。所以前端不能靠「有没有抛异常」判断成败，
/// 必须看 [ok]。
///
/// [errorKind] 沿用后端 ADR-0038 的归因枚举（auth / rate_limit / network /
/// bad_request / unknown）+ `timeout`，用于给出可操作的下一步。
class ModelProbeResult {
  final bool ok;
  final int latencyMs;
  final String message;
  final String? errorKind;
  final String? detail;

  const ModelProbeResult({
    required this.ok,
    required this.latencyMs,
    required this.message,
    this.errorKind,
    this.detail,
  });

  factory ModelProbeResult.fromJson(Map<String, dynamic> json) {
    return ModelProbeResult(
      ok: json['ok'] as bool? ?? false,
      latencyMs: json['latency_ms'] as int? ?? 0,
      message: json['message'] as String? ?? '',
      errorKind: json['error_kind'] as String?,
      detail: json['detail'] as String?,
    );
  }
}

class ModelListResp {
  final List<ModelInfo> custom;

  const ModelListResp({this.custom = const []});

  factory ModelListResp.fromJson(Map<String, dynamic> json) {
    return ModelListResp(
      custom: (json['custom'] as List? ?? [])
          .map((e) => ModelInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
