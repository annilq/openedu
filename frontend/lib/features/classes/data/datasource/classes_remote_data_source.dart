import '../../../../shared/data/remote/network_service.dart';

/// 班级远端数据源：仅封装 `GET /classes` 原始请求与响应形状。
///
/// 与 students feature 的 datasource 同一套路（ADR-0036 分层）：不认识领域模型，
/// 只把后端 JSON 原样交还，领域转换留在 repository 层。
class ClassesRemoteDataSource {
  final NetworkService _network;
  ClassesRemoteDataSource(this._network);

  Future<List<dynamic>> getClasses() async {
    final data = await _network.get('/classes');
    return data as List<dynamic>;
  }

  /// 新建班级（ADR-0086 班级管理）。
  Future<Map<String, dynamic>> createClass({
    required String name,
    required int grade,
  }) async {
    final data = await _network.post(
      '/classes',
      body: {'name': name, 'grade': grade},
    );
    return data as Map<String, dynamic>;
  }

  /// 重命名 / 改年级（ADR-0086）。
  Future<Map<String, dynamic>> updateClass(
    String id, {
    required String name,
    required int grade,
  }) async {
    final data = await _network.patch(
      '/classes/$id',
      body: {'name': name, 'grade': grade},
    );
    return data as Map<String, dynamic>;
  }

  /// 删除班级：仅置空学生 class_id（ADR-0068/0086）。
  Future<void> deleteClass(String id) async {
    await _network.delete('/classes/$id');
  }
}
