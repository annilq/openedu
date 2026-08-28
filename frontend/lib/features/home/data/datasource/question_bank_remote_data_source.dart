import '../../../../shared/data/remote/network_service.dart';
import '../../../../shared/domain/models/models.dart';

/// 题库数据源：题库浏览 + 从题库组卷（选项 A / 选项 B）。
/// 端点不包外层（与 /tasks/batch-generate 一致，NetworkService 返回 FastAPI 原响应体）。
class QuestionBankRemoteDataSource {
  final NetworkService _network;
  QuestionBankRemoteDataSource(this._network);

  Future<BankListResp> getQuestions({
    String? subject,
    int? grade,
    String? knowledgePoint,
    String? qtype,
    String? keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (subject != null && subject.isNotEmpty) query['subject'] = subject;
    if (grade != null) query['grade'] = grade;
    if (knowledgePoint != null && knowledgePoint.isNotEmpty) {
      query['knowledge_point'] = knowledgePoint;
    }
    if (qtype != null && qtype.isNotEmpty) query['qtype'] = qtype;
    if (keyword != null && keyword.isNotEmpty) query['keyword'] = keyword;
    final data = await _network.get('/questions', query: query);
    return BankListResp.fromJson(data as Map<String, dynamic>);
  }

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
    return TaskModel.fromJson(data as Map<String, dynamic>);
  }

  Future<TaskModel> addToTaskFromBank({
    required String taskId,
    required List<String> questionIds,
  }) async {
    final data = await _network.post(
      '/tasks/$taskId/questions/from-bank',
      body: {'question_ids': questionIds},
    );
    return TaskModel.fromJson(data as Map<String, dynamic>);
  }

  /// 选项 B 草稿选择器：家长草稿列表（GET /tasks?status=draft）。
  Future<List<TaskModel>> getDraftTasks() async {
    final data = await _network.get('/tasks', query: {'status': 'draft'});
    return (data as List)
        .map((e) => TaskModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
