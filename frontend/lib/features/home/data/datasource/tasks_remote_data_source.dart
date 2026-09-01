import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';

/// 家长任务数据源：拉取本家长全部任务（按创建时间倒序）。
/// 后端 GET /tasks 支持 ?status= 过滤；此处取全量后在客户端按状态分 Tab，
/// 避免多次请求、且不会漏掉 ready（待派发）等中间态。
class TasksRemoteDataSource {
  final NetworkService _network;
  TasksRemoteDataSource(this._network);

  Future<List<TaskModel>> getTasks() async {
    final data = await _network.get('/tasks');
    return (data as List)
        .map((e) => TaskModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
