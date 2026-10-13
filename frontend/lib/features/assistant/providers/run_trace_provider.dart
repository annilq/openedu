import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/run_trace_repository_impl.dart';
import '../domain/repositories/run_trace_repository.dart';
import '../domain/run_trace.dart';

/// assistant feature 组合根（运行轨迹部分，ADR-0088 ticket 02）。
///
/// 与 `assistant_provider.dart` 并列：那里装配会话历史（气泡口径），这里装配
/// 运行轨迹（全步骤口径）。View 层只认 [runTraceRepositoryProvider] 这个端口。
final runTraceRepositoryProvider = Provider<RunTraceRepository>((ref) {
  return RunTraceRepositoryImpl(ref.watch(networkServiceProvider));
});

/// 运行轨迹列表。
///
/// `autoDispose`：离开轨迹页就释放，下次进来重新取——运行可能刚在别处发生，
/// 缓存快照会过时（同 `conversationHistoryProvider` 显式 invalidate 的思路，
/// 这里连 invalidate 都省了）。
final runTraceListProvider =
    FutureProvider.autoDispose<List<RunTraceRun>>((ref) async {
  return ref.watch(runTraceRepositoryProvider).runs();
});

/// 一次运行的全部步骤（按 turn 正序）。
final runTraceDetailProvider = FutureProvider.autoDispose
    .family<RunTraceDetail, String>((ref, runId) async {
  return ref.watch(runTraceRepositoryProvider).detail(runId);
});
