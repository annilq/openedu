import '../../data/datasource/analytics_remote_data_source.dart';
import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/analytics_repository.dart';

class AnalyticsRepositoryImpl implements AnalyticsRepository {
  final AnalyticsRemoteDataSource _dataSource;

  AnalyticsRepositoryImpl(this._dataSource);

  @override
  Future<WrongDistributionResp> getWrongDistribution({
    required String scope,
    String? classId,
    required String dimension,
  }) =>
      _dataSource.getWrongDistribution(
        scope: scope,
        classId: classId,
        dimension: dimension,
      );

  @override
  Future<AccuracyResp> getAccuracy({
    required String scope,
    String? classId,
    required String dimension,
  }) =>
      _dataSource.getAccuracy(
        scope: scope,
        classId: classId,
        dimension: dimension,
      );

  @override
  Future<MasteryResp> getMastery({
    required String scope,
    String? classId,
  }) =>
      _dataSource.getMastery(
        scope: scope,
        classId: classId,
      );
}
