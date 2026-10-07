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
}
