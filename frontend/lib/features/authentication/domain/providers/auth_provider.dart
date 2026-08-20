import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/providers/core_providers.dart';
import '../../data/datasource/auth_remote_data_source.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_notifier.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  final dataSource = AuthRemoteDataSource(network);
  return AuthRepositoryImpl(dataSource, storage, network);
});

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthNotifier(repo);
});
