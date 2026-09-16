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
  Future<CursorPage<WrongQuestionModel>> childWrongQuestions({
    String? cursor,
    int pageSize = 20,
  }) async {
    final data = await _network.get('/tasks/wrong-questions', query: {
      'page_size': pageSize,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    });
    return CursorPage.fromJson(decodeMap(data), WrongQuestionModel.fromJson);
  }

  @override
  Future<WrongQuestionPage> parentWrongQuestions(
    String childId, {
    String? cursor,
    int pageSize = 20,
    String scope = 'active',
  }) async {
    final data = await _network.get(
      '/tasks/children/$childId/wrong-questions',
      query: {
        'page_size': pageSize,
        'scope': scope,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    return WrongQuestionPage.fromJson(decodeMap(data));
  }

  @override
  Future<WrongQuestionModel> rejoinWrongQuestion(
    String childId,
    String wrongQuestionId,
  ) async {
    final data = await _network.post(
      '/tasks/children/$childId/wrong-questions/$wrongQuestionId/rejoin',
    );
    return WrongQuestionModel.fromJson(decodeMap(data));
  }
}
