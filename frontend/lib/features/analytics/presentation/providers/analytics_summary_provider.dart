import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../../providers/analytics_provider.dart';

/// 教师工作台「速览层」专用只读聚合（ADR-0075 §2.5）。
///
/// 与 [analyticsNotifierProvider]（分析层，带 scope/class + 维度下钻）**分离**：
/// 速览固定 `scope=all`，永不跟随分析层的班级/维度切换——否则用户在分析层切到
/// 某班级后，顶部速览的掌握度/错题也会跟着变，破坏「进入即看全体教师概览」的语义。
///
/// 三份聚合端点与统计页同源（[AnalyticsRepository]，无新后端逻辑）；错题分布与正确率
/// 取 `dimension='subject'` 使速览只有少数类目、图表干净（掌握度无维度参数，直接 scope=all）。
sealed class AnalyticsSummaryState {
  const AnalyticsSummaryState();
}

class AnalyticsSummaryInitial extends AnalyticsSummaryState {
  const AnalyticsSummaryInitial();
}

class AnalyticsSummaryLoading extends AnalyticsSummaryState {
  const AnalyticsSummaryLoading();
}

class AnalyticsSummaryLoaded extends AnalyticsSummaryState {
  final WrongDistributionResp wrong;
  final AccuracyResp accuracy;
  final MasteryResp mastery;

  const AnalyticsSummaryLoaded({
    required this.wrong,
    required this.accuracy,
    required this.mastery,
  });
}

class AnalyticsSummaryError extends AnalyticsSummaryState {
  final String message;
  const AnalyticsSummaryError(this.message);
}

class AnalyticsSummaryNotifier extends StateNotifier<AnalyticsSummaryState> {
  final AnalyticsRepository _analytics;
  AnalyticsSummaryNotifier(this._analytics)
      : super(const AnalyticsSummaryInitial());

  Future<void> load() async {
    state = const AnalyticsSummaryLoading();
    try {
      final results = await Future.wait([
        _analytics.getWrongDistribution(
          scope: 'all',
          classId: null,
          dimension: 'subject',
        ),
        _analytics.getAccuracy(
          scope: 'all',
          classId: null,
          dimension: 'subject',
        ),
        _analytics.getMastery(scope: 'all'),
      ]);
      state = AnalyticsSummaryLoaded(
        wrong: results[0] as WrongDistributionResp,
        accuracy: results[1] as AccuracyResp,
        mastery: results[2] as MasteryResp,
      );
    } catch (e) {
      state = AnalyticsSummaryError(e.toString());
    }
  }
}

final analyticsSummaryProvider =
    StateNotifierProvider<AnalyticsSummaryNotifier, AnalyticsSummaryState>((ref) {
  return AnalyticsSummaryNotifier(ref.watch(analyticsRepositoryProvider));
});
