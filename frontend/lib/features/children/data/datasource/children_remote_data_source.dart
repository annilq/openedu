import '../../../../shared/data/remote/network_service.dart';

class ChildrenRemoteDataSource {
  final NetworkService _network;
  ChildrenRemoteDataSource(this._network);

  Future<Map<String, dynamic>> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
  }) async {
    final body = {
      'username': username,
      'password': password,
      'display_name': displayName,
    };
    if (grade != null) body['grade'] = grade;
    return await _network.post('/children', body: body);
  }

  Future<List<dynamic>> getChildren() async {
    final data = await _network.get('/children');
    return (data as Map<String, dynamic>)['data'] as List<dynamic>;
  }
}
