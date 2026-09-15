import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/utils/json_decode.dart';
import '../../domain/repositories/tasks_repository.dart';

class TasksRepositoryImpl implements TasksRepository {
  TasksRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<List<TaskModel>> todayTasks() async {
    final data = await _network.get('/tasks/today');
    return decodeList(data, TaskModel.fromJson);
  }

  @override
  Future<List<TaskModel>> parentTasks() async {
    final data = await _network.get('/tasks');
    return decodeList(data, TaskModel.fromJson);
  }

  @override
  Future<ProgressModel> progress(String childId) async {
    final data = await _network.get('/tasks/children/$childId/progress');
    return ProgressModel.fromJson(decodeMap(data));
  }

  @override
  Future<MasteryModel> mastery(String childId) async {
    final data = await _network.get('/tasks/children/$childId/mastery');
    return MasteryModel.fromJson(decodeMap(data));
  }

  @override
  Future<TaskModel> persistGenerated(Map<String, dynamic> body) async {
    final data = await _network.post('/tasks/from-generated', body: body);
    return TaskModel.fromJson(decodeMap(data));
  }
}
