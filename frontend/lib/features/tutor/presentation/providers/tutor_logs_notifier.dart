import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../../../shared/presentation/resource.dart';

/// 家长端「AI 答疑记录」日志（F-305）：GET /tutor/logs?child_id=
///
/// 这是 `features/tutor` 端点层唯一保留的职责——家长侧可观测日志，非 AI 生成端点，
/// 因此不并入 `POST /assistant/chat`（ADR-0024/0036）。娃娃端实时答疑的旧
/// `TutorNotifier` / `TutorChatScreen` 已随 ADR-0036 收敛删除。
final tutorLogsNotifierProvider = StateNotifierProvider<
    ParamResourceNotifier<List<TutorLogModel>, String>,
    Resource<List<TutorLogModel>>>(
  (ref) => ParamResourceNotifier(
    ref.watch(networkServiceProvider),
    pathOf: (_) => '/tutor/logs',
    queryOf: (childId) => {'child_id': childId},
    parse: (d) => decodeList(d, TutorLogModel.fromJson),
  ),
);
