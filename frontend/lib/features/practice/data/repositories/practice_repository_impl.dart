import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/utils/json_decode.dart';
import '../../domain/repositories/practice_repository.dart';

/// 练习作答实现。
///
/// 不另建 `PracticeRemoteDataSource`：那只会是 `_network.post(...)` 的转发
/// （pass-through，非深模块）。端点与模型映射就是本层该干的活，落在实现类里正好。
class PracticeRepositoryImpl implements PracticeRepository {
  PracticeRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<AnswerResultModel> submitAnswer(
    String taskId,
    String questionId,
    String answer,
  ) async {
    final data = await _network.post(
      '/tasks/$taskId/answer',
      body: {
        'question_id': questionId,
        'student_answer': answer,
      },
    );
    return AnswerResultModel.fromJson(decodeMap(data));
  }

  @override
  Future<bool> checkin(String taskId) async {
    try {
      await _network.post('/tasks/$taskId/checkin');
      return true;
    } catch (_) {
      return false;
    }
  }
}
