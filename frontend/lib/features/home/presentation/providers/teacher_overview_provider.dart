import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/domain/models/analytics_models.dart';
import '../../../analytics/domain/repositories/analytics_repository.dart';
import '../../../analytics/providers/analytics_provider.dart';

/// 教师整体概览聚合（ADR-0070 收尾）：班级维度的掌握度 / 错题汇总，**不绑定单个学生**。
/// 数据复用 analytics 仓库的两个聚合端点（scope=all），与「学情统计」分工：
/// 本 provider 给「概览」页做进入即看的速览，统计页做带下钻的深入分析。
sealed class TeacherOverviewState {
  const TeacherOverviewState();
}

class TeacherOverviewInitial extends TeacherOverviewState {
  const TeacherOverviewInitial();
}

class TeacherOverviewLoading extends TeacherOverviewState {
  const TeacherOverviewLoading();
}

class TeacherOverviewLoaded extends TeacherOverviewState {
  final int masteredCount;
  final int totalKnowledgePoints;
  final int activeWrong;
  final List<MasteryGroup> weakItems;

  const TeacherOverviewLoaded({
    required this.masteredCount,
    required this.totalKnowledgePoints,
    required this.activeWrong,
    required this.weakItems,
  });
}

class TeacherOverviewError extends TeacherOverviewState {
  final String message;
  const TeacherOverviewError(this.message);
}

class TeacherOverviewNotifier extends StateNotifier<TeacherOverviewState> {
  final AnalyticsRepository _analytics;
  TeacherOverviewNotifier(this._analytics)
      : super(const TeacherOverviewInitial());

  Future<void> load() async {
    state = const TeacherOverviewLoading();
    try {
      final wrong = await _analytics.getWrongDistribution(
        scope: 'all',
        dimension: 'knowledge_point',
      );
      final mastery = await _analytics.getMastery(scope: 'all');
      final weak = [...mastery.items]
        ..sort((a, b) => b.activeWrong.compareTo(a.activeWrong));
      state = TeacherOverviewLoaded(
        masteredCount: mastery.masteredCount,
        totalKnowledgePoints: mastery.totalKnowledgePoints,
        activeWrong: wrong.totalActive,
        weakItems: weak.where((m) => m.activeWrong > 0).toList(),
      );
    } catch (e) {
      state = TeacherOverviewError(e.toString());
    }
  }
}

final teacherOverviewProvider =
    StateNotifierProvider<TeacherOverviewNotifier, TeacherOverviewState>((ref) {
  return TeacherOverviewNotifier(ref.watch(analyticsRepositoryProvider));
});
