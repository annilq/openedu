import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/utils/json_decode.dart';
import '../../domain/repositories/review_repository.dart';

class ReviewRepositoryImpl implements ReviewRepository {
  ReviewRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<List<ReviewItemModel>> dueReview() async {
    final data = await _network.get('/review/due');
    return decodeList(data, ReviewItemModel.fromJson);
  }

  @override
  Future<AnswerResultModel> answer(
    String wrongQuestionId,
    String studentAnswer,
  ) async {
    final data = await _network.post('/review/answer', body: {
      'wrong_question_id': wrongQuestionId,
      'student_answer': studentAnswer,
    });
    return AnswerResultModel.fromJson(decodeMap(data));
  }

  @override
  Future<List<WrongQuestionModel>> childWrongQuestions() async {
    final data = await _network.get('/tasks/wrong-questions');
    return decodeList(data, WrongQuestionModel.fromJson);
  }

  @override
  Future<List<WrongQuestionModel>> parentWrongQuestions(String childId) async {
    final data =
        await _network.get('/tasks/children/$childId/wrong-questions');
    return decodeList(data, WrongQuestionModel.fromJson);
  }
}
