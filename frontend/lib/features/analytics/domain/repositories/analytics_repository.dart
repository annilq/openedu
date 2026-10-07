import '../models/analytics_models.dart';

/// 学情统计仓库抽象（ADR-0036：presentation 只依赖此接口，不认识 datasource）。
///
/// 三个聚合端点共享「解析三态作用域 → 批量聚合」语义，返回体见
/// [analytics_models.dart]。作用域 [scope] ∈ {all, class, student}；
/// [dimension] ∈ {subject, grade, semester, knowledge_point}。
abstract class AnalyticsRepository {
  Future<WrongDistributionResp> getWrongDistribution({
    required String scope,
    String? studentId,
    String? classId,
    required String dimension,
  });

  Future<AccuracyResp> getAccuracy({
    required String scope,
    String? studentId,
    String? classId,
    required String dimension,
  });

  Future<MasteryResp> getMastery({
    required String scope,
    String? studentId,
    String? classId,
  });
}
