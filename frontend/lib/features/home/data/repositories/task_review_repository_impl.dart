import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/utils/json_decode.dart';
import '../../domain/repositories/task_review_repository.dart';

class TaskReviewRepositoryImpl implements TaskReviewRepository {
  TaskReviewRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<TaskModel> load(String taskId) async {
    final data = await _network.get('/tasks/$taskId');
    return TaskModel.fromJson(decodeMap(data));
  }

  @override
  Future<QuestionModel> promoteOne({
    required String taskId,
    required String tqId,
  }) async {
    final data = await _network.post('/tasks/$taskId/questions/$tqId/promote');
    return QuestionModel.fromJson(decodeMap(data));
  }

  @override
  Future<TaskModel> promoteAll(String taskId) async {
    final data = await _network.post('/tasks/$taskId/promote-all');
    return TaskModel.fromJson(decodeMap(data));
  }

  @override
  Future<void> removeOne({required String taskId, required String tqId}) =>
      _network.delete('/tasks/$taskId/questions/$tqId');

  @override
  Future<QuestionModel> editOne({
    required String taskId,
    required String tqId,
    required Map<String, dynamic> edits,
  }) async {
    final data = await _network.put(
      '/tasks/$taskId/questions/$tqId',
      body: edits,
    );
    return QuestionModel.fromJson(decodeMap(data));
  }

  @override
  Future<TaskModel> editMeta({
    required String taskId,
    required Map<String, dynamic> edits,
  }) async {
    final data = await _network.put('/tasks/$taskId', body: edits);
    return TaskModel.fromJson(decodeMap(data));
  }

  @override
  Future<TaskModel> confirm(String taskId) async {
    final data = await _network.post('/tasks/$taskId/confirm');
    return TaskModel.fromJson(decodeMap(data));
  }

  @override
  Future<TaskModel> assign({
    required String taskId,
    required String childId,
  }) async {
    final data =
        await _network.post('/tasks/$taskId/assign?child_id=$childId');
    return TaskModel.fromJson(decodeMap(data));
  }

  @override
  Future<void> discard(String taskId) => _network.delete('/tasks/$taskId');
}
