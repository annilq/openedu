import 'dart:convert';

import 'package:genkit/client.dart';

import '../../../configs/app_config.dart';
import '../../domain/models/models.dart';
import '../local/storage_service.dart';

/// Genkit 全栈 AI 客户端（ADR-0015 / 迁移 08b）：通过 `package:genkit/client.dart` 的
/// `defineRemoteAction` 直连后端 `genkit_fastapi.handle_genkit_request` 暴露的
/// 原生 action 端点（`/ai/tutor/ask`、`/ai/tasks/generate`）。
///
/// 线协议与后端 100% 对齐（已逐字节核对 `genkit_fastapi/handler.py`）：
/// - 请求体 `{'data': input}`（非流式 `Content-Type: application/json`；流式追加
///   `Accept: text/event-stream`）。
/// - 流式逐帧 `data: {"message": <chunk>}`（每片段）+ 末帧 `data: {"result": <output>}`。
/// - 错误：非流式 `{"detail": ...}`（FastAPI 原始）；流式 `error: {"message": ...}` 帧，
///   二者均被 Dart 端以 [GenkitException] 抛出（原始体在 [GenkitException.details]）。
///
/// 鉴权：Dart 原生 `http.Client` 不经 Dio 拦截器，故 Bearer token 由 [StorageService]
/// 取出后逐次经 `headers:` 注入（与 Dio 拦截器等价时机）。
class GenkitAiClient {
  final StorageService _storage;

  late final RemoteAction<Map<String, dynamic>, TutorReply, String, dynamic>
      _tutorAsk;
  late final RemoteAction<Map<String, dynamic>, List<QuestionPreview>,
      TaskGenChunk, dynamic> _tasksGenerate;

  GenkitAiClient(this._storage) {
    final base = AppConfig.apiBaseUrl;
    _tutorAsk = defineRemoteAction<Map<String, dynamic>, TutorReply, String,
        dynamic>(
      url: '$base/ai/tutor/ask',
      fromResponse: (d) => TutorReply.fromJson(d as Map<String, dynamic>),
      fromStreamChunk: (d) => d as String,
    );
    _tasksGenerate = defineRemoteAction<Map<String, dynamic>,
        List<QuestionPreview>, TaskGenChunk, dynamic>(
      url: '$base/ai/tasks/generate',
      fromResponse: (d) =>
          (d as List).map((e) => QuestionPreview.fromJson(e as Map<String, dynamic>)).toList(),
      fromStreamChunk: (d) => TaskGenChunk.fromJson(d as Map<String, dynamic>),
    );
  }

  Map<String, String> _authHeaders() {
    final token = _storage.getToken();
    return token != null ? {'Authorization': 'Bearer $token'} : const {};
  }

  /// 非流式答疑：返回最终 [TutorReply]（兜底 / 测试用）。
  Future<TutorReply> askTutor(Map<String, dynamic> input) =>
      _tutorAsk.call(input: input, headers: _authHeaders());

  /// 流式答疑：逐 token（`String`）产出，末帧 [ActionStream.onResult] 为 [TutorReply]。
  ActionStream<String, TutorReply> streamTutor(Map<String, dynamic> input) =>
      _tutorAsk.stream(input: input, headers: _authHeaders());

  /// 非流式出题：返回题卡列表。
  Future<List<QuestionPreview>> generateTasks(Map<String, dynamic> input) =>
      _tasksGenerate.call(input: input, headers: _authHeaders());

  /// 流式出题：逐信封 chunk（[TaskGenChunk]：STEP/REASONING/CARD）产出，
  /// 末帧 [ActionStream.onResult] 为题卡列表（[QuestionPreview]）。
  ActionStream<TaskGenChunk, List<QuestionPreview>> streamTasks(
          Map<String, dynamic> input) =>
      _tasksGenerate.stream(input: input, headers: _authHeaders());
}

/// 将 [GenkitException] 转成用户可读文案。
///
/// 后端在路由器层（auth / 配额 / 输入安全）以非 2xx 返回的原始 FastAPI 错误体形如
/// `{"detail": "..."}`（非流式）或 `{"error": {"message": "..."}}`（流式 `error:` 帧），
/// 由 [GenkitException.details] 携带；此处尽力解析出友好信息。
String friendlyGenkitError(GenkitException e) {
  final details = e.details;
  if (details != null && details.isNotEmpty) {
    try {
      final parsed = jsonDecode(details);
      if (parsed is Map) {
        final detail = parsed['detail'];
        if (detail is String && detail.isNotEmpty) return '⏳ $detail';
        if (detail is Map && detail['msg'] is String) return '⏳ ${detail['msg']}';
        final err = parsed['error'];
        if (err is Map && err['message'] is String) return '⏳ ${err['message']}';
      }
    } catch (_) {
      // details 非 JSON（连接层原始文本）时回退到 message。
    }
  }
  if (e.message.isNotEmpty) return '⏳ ${e.message}';
  return '⏳ 请求失败，请稍后重试';
}
