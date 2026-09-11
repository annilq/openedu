import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/providers/core_providers.dart';
import '../../../../shared/presentation/resource.dart';
import '../../../../shared/domain/models/models.dart';

/// 家长任务列表（本家长全部任务，后端已按 created_at 倒序）。
///
/// 纯资源加载，直接走 [NetworkService]——此前中间还夹了一层
/// `TasksRemoteDataSource`，它只是 `_network.get('/tasks')` + map 的转发，
/// 删掉后复杂度没有消失，只是回到该在的地方（删除测试：pass-through，非深模块）。
final parentTasksNotifierProvider =
    StateNotifierProvider<ResourceNotifier<List<TaskModel>>, Resource<List<TaskModel>>>(
  (ref) => ResourceNotifier(
    ref.watch(networkServiceProvider),
    path: '/tasks',
    parse: (d) => decodeList(d, TaskModel.fromJson),
  ),
);
