import '../../../../shared/data/remote/network_service.dart';
import '../../domain/models/analytics_models.dart';

/// 学情统计远端数据源：仅封装三个聚合端点的原始请求与响应解包（ADR-0036 分层）。
///
/// 与 classes/students 的 datasource 同一套路：不认识领域模型，只把后端 JSON
/// 原样交还（成功响应是裸 dict，错误由 DioNetworkService 统一转 AppException）。
class AnalyticsRemoteDataSource {
  final NetworkService _network;
  AnalyticsRemoteDataSource(this._network);

  /// 错题分布：`GET /analytics/wrong-distribution`。
  Future<WrongDistributionResp> getWrongDistribution({
    required String scope,
    String? studentId,
    String? classId,
    required String dimension,
  }) async {
    final data = await _network.get(
      '/analytics/wrong-distribution',
      query: _query(scope, studentId, classId, {'dimension': dimension}),
    );
    return WrongDistributionResp.fromJson(data as Map<String, dynamic>);
  }

  /// 正确率：`GET /analytics/accuracy`（source 默认 all，界面不拆练习/复习来源切换）。
  Future<AccuracyResp> getAccuracy({
    required String scope,
    String? studentId,
    String? classId,
    required String dimension,
  }) async {
    final data = await _network.get(
      '/analytics/accuracy',
      query: _query(scope, studentId, classId,
          {'dimension': dimension, 'source': 'all'}),
    );
    return AccuracyResp.fromJson(data as Map<String, dynamic>);
  }

  /// 掌握度：`GET /analytics/mastery`（按知识点跨作用域批量聚合）。
  Future<MasteryResp> getMastery({
    required String scope,
    String? studentId,
    String? classId,
  }) async {
    final data = await _network.get(
      '/analytics/mastery',
      query: _query(scope, studentId, classId, {}),
    );
    return MasteryResp.fromJson(data as Map<String, dynamic>);
  }

  /// 拼查询参数：作用域三态 + 条件性学生/班级 id + 其余维度参数。
  Map<String, dynamic> _query(
    String scope,
    String? studentId,
    String? classId,
    Map<String, dynamic> extra,
  ) =>
      {
        'scope': scope,
        if (studentId != null) 'student_id': studentId,
        if (classId != null) 'class_id': classId,
        ...extra,
      };
}
