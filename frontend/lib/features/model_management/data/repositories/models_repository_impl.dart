import '../../../../shared/data/remote/network_service.dart';
import '../../domain/models.dart';
import '../../../../shared/utils/json_decode.dart';
import '../../domain/model_requests.dart';
import '../../domain/repositories/models_repository.dart';

class ModelsRepositoryImpl implements ModelsRepository {
  ModelsRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<ModelListResp> list() async {
    final data = await _network.get('/models');
    return ModelListResp.fromJson(decodeMap(data));
  }

  @override
  Future<List<ModelProviderPreset>> providers() async {
    final data = await _network.get('/models/providers');
    return decodeList(data, ModelProviderPreset.fromJson);
  }

  @override
  Future<void> create(ModelCreateReq req) =>
      _network.post('/models', body: req.toJson());

  @override
  Future<void> update(String id, ModelUpdateReq req) =>
      _network.put('/models/$id', body: req.toJson());

  @override
  Future<void> delete(String id) => _network.delete('/models/$id');

  @override
  Future<void> setDefault(String id) =>
      _network.put('/models/default', body: {'id': id});
}
