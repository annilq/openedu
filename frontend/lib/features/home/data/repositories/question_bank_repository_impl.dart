import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';
import '../../../../shared/utils/json_decode.dart';
import '../../domain/repositories/question_bank_repository.dart';

/// 题库实现：端点不包外层（与 /tasks/batch-generate 一致，
/// [NetworkService] 返回 FastAPI 原响应体）。
///
/// 由原 `QuestionBankRemoteDataSource` 升格而来——查询拼装 + 模型映射本就是
/// repository 该干的活，中间再垫一层只做转发的 datasource 属于 pass-through。
class QuestionBankRepositoryImpl implements QuestionBankRepository {
  QuestionBankRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<BankListResp> getQuestions({
    String? subject,
    int? grade,
    String? knowledgePoint,
    String? qtype,
    String? keyword,
    String? cursor,
    int pageSize = 20,
  }) async {
    final query = <String, dynamic>{
      'page_size': pageSize,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    if (subject != null && subject.isNotEmpty) query['subject'] = subject;
    if (grade != null) query['grade'] = grade;
    if (knowledgePoint != null && knowledgePoint.isNotEmpty) {
      query['knowledge_point'] = knowledgePoint;
    }
    if (qtype != null && qtype.isNotEmpty) query['qtype'] = qtype;
    if (keyword != null && keyword.isNotEmpty) query['keyword'] = keyword;
    final data = await _network.get('/questions', query: query);
    return CursorPage.fromJson(
      decodeMap(data),
      BankQuestionItem.fromJson,
    );
  }

  @override
  Future<TaskModel> createTaskFromBank({
    required String title,
    required String childId,
    required List<String> questionIds,
  }) async {
    final data = await _network.post('/tasks/from-bank', body: {
      'title': title,
      'child_id': childId,
      'question_ids': questionIds,
    });
    return TaskModel.fromJson(decodeMap(data));
  }

  @override
  Future<TaskModel> addToTaskFromBank({
    required String taskId,
    required List<String> questionIds,
  }) async {
    final data = await _network.post(
      '/tasks/$taskId/questions/from-bank',
      body: {'question_ids': questionIds},
    );
    return TaskModel.fromJson(decodeMap(data));
  }

  @override
  Future<List<TaskModel>> getDraftTasks() async {
    // GET /tasks 响应在 ADR-0053 后是游标信封（不再内嵌题目），草稿选择器只取 items。
    final data = await _network.get('/tasks', query: {'status': 'draft'});
    return TaskPage.fromJson(decodeMap(data)).items;
  }

  @override
  Future<DeleteQuestionsResult> deleteQuestions(List<String> ids) async {
    final data = await _network.delete('/questions', body: {'ids': ids});
    return DeleteQuestionsResult.fromJson(decodeMap(data));
  }

  @override
  Future<List<QuestionUsageItem>> getQuestionUsages(String questionId) async {
    final data = await _network.get('/questions/$questionId/usages');
    return decodeList(data, QuestionUsageItem.fromJson);
  }

  @override
  Future<TaskModel> getTaskById(String taskId) async {
    final data = await _network.get('/tasks/$taskId');
    return TaskModel.fromJson(decodeMap(data));
  }
}
