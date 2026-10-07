import '../../data/datasource/analytics_remote_data_source.dart';
import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/analytics_repository.dart';

class AnalyticsRepositoryImpl implements AnalyticsRepository {
  final AnalyticsRemoteDataSource _dataSource;

  AnalyticsRepositoryImpl(this._dataSource);

  @override
  Future<WrongDistributionResp> getWrongDistribution({
    required String scope,
    String? studentId,
    String? classId,
    required String dimension,
  }) =>
      _dataSource.getWrongDistribution(
        scope: scope,
        studentId: studentId,
        classId: classId,
        dimension: dimension,
      );

  @override
  Future<AccuracyResp> getAccuracy({
    required String scope,
    String? studentId,
    String? classId,
    required String dimension,
  }) =>
      _dataSource.getAccuracy(
        scope: scope,
        studentId: studentId,
        classId: classId,
        dimension: dimension,
      );

  @override
  Future<MasteryResp> getMastery({
    required String scope,
    String? studentId,
    String? classId,
  }) =>
      _dataSource.getMastery(
        scope: scope,
        studentId: studentId,
        classId: classId,
      );
}
