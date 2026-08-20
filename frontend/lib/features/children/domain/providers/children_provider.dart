import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/providers/core_providers.dart';
import '../../data/datasource/children_remote_data_source.dart';
import '../../data/repositories/children_repository_impl.dart';
import '../../domain/repositories/children_repository.dart';
import '../../presentation/providers/children_notifier.dart';

final childrenRepositoryProvider = Provider<ChildrenRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  final dataSource = ChildrenRemoteDataSource(network);
  return ChildrenRepositoryImpl(dataSource);
});

final childrenNotifierProvider =
    StateNotifierProvider<ChildrenNotifier, ChildrenState>((ref) {
  final repo = ref.watch(childrenRepositoryProvider);
  return ChildrenNotifier(repo);
});
