import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/providers/core_providers.dart';
import '../data/datasource/analytics_remote_data_source.dart';
import '../data/repositories/analytics_repository_impl.dart';
import '../domain/repositories/analytics_repository.dart';

/// 学情统计 feature 的组合根（与 `classes_provider.dart` 同款结构，ADR-0058）。
///
/// 仅暴露 [analyticsRepositoryProvider]：聚合取数被统计页的 notifier 消费。
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  return AnalyticsRepositoryImpl(AnalyticsRemoteDataSource(network));
});
