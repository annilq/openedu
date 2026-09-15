import '../../../../shared/data/remote/network_service.dart';
import '../../domain/models.dart';
import '../../../../shared/utils/json_decode.dart';
import '../../domain/repositories/tutor_logs_repository.dart';

class TutorLogsRepositoryImpl implements TutorLogsRepository {
  TutorLogsRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<List<TutorLogModel>> logs(String childId) async {
    final data = await _network.get(
      '/tutor/logs',
      query: {'child_id': childId},
    );
    return decodeList(data, TutorLogModel.fromJson);
  }
}
