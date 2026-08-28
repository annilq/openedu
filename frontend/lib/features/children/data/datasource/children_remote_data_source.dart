import '../../../../shared/data/remote/network_service.dart';

class ChildrenRemoteDataSource {
  final NetworkService _network;
  ChildrenRemoteDataSource(this._network);

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
    return await _network.post('/children', body: body);
  }

  Future<Map<String, dynamic>> updateChild({
    required String childId,
    String? displayName,
    int? grade,
    Map<String, dynamic>? interests,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (grade != null) body['grade'] = grade;
    if (interests != null) body['interests'] = interests;
    return await _network.put('/children/$childId', body: body);
  }

  Future<List<dynamic>> getChildren() async {
    final data = await _network.get('/children');
    return (data as Map<String, dynamic>)['data'] as List<dynamic>;
  }
}
