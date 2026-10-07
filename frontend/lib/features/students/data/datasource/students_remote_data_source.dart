import '../../../../shared/data/remote/network_service.dart';

class StudentsRemoteDataSource {
  final NetworkService _network;
  StudentsRemoteDataSource(this._network);

  Future<Map<String, dynamic>> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
    Map<String, dynamic>? interests,
  }) async {
    final body = <String, dynamic>{
      'username': username,
      'password': password,
      'display_name': displayName,
    };
    if (grade != null) body['grade'] = grade;
    // 兴趣画像：全空则不下传（后端 interests 默认 None）。
    if (interests != null) body['interests'] = interests;
    return await _network.post('/students', body: body);
  }

  Future<Map<String, dynamic>> updateChild({
    required String studentId,
    String? displayName,
    int? grade,
    Map<String, dynamic>? interests,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (grade != null) body['grade'] = grade;
    if (interests != null) body['interests'] = interests;
    return await _network.put('/students/$studentId', body: body);
  }

  Future<List<dynamic>> getChildren() async {
    final data = await _network.get('/students');
    return (data as Map<String, dynamic>)['data'] as List<dynamic>;
  }

  /// 学生管理页取数（ADR-0068 §2.3 / ticket 02）：在后端 `GET /students` 之上叠加
  /// 班级筛选与姓名/学号搜索。
  ///
  /// - [classId] 非 null → 仅该班学生（后端 `class_id` 过滤）；
  /// - [keyword] 非 null/空 → 后端按姓名/学号模糊匹配。
  /// 「未分班」与「全部」由调用方在取到全量后客户端二次过滤，避免新增后端参数。
  Future<List<dynamic>> getStudents({
    String? classId,
    String? keyword,
  }) async {
    final query = <String, dynamic>{};
    if (classId != null) query['class_id'] = classId;
    if (keyword != null && keyword.isNotEmpty) query['keyword'] = keyword;
    final data =
        await _network.get('/students', query: query.isEmpty ? null : query);
    return (data as Map<String, dynamic>)['data'] as List<dynamic>;
  }

  /// 各学生活跃（未毕业）错题数：`GET /students/wrong-question-counts` 返回
  /// `{student_id: count}`，供学生管理页每行醒目展示（ADR-0068 §2.3）。
  Future<Map<String, int>> getWrongQuestionCounts() async {
    final data =
        await _network.get('/students/wrong-question-counts');
    return (data as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));
  }
}
