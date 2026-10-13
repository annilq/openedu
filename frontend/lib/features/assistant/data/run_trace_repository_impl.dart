import '../../../shared/data/remote/network_service.dart';
import '../../../shared/utils/json_decode.dart';
import '../domain/run_trace.dart';
import '../domain/repositories/run_trace_repository.dart';

/// 运行轨迹适配器：`GET /ai/debug/conversations`（列表）与 `/{id}`（详情）。
///
/// 与 [AssistantRepositoryImpl] 读同一张后端 `Conversation`/`Message` 表，但走
/// **debug 端点**（ADR-0022/0026 的教师调试轨迹）而非 `/assistant/conversations`：
/// 后者把内部步骤剥成气泡，前者原样返回全部步骤——两种口径在端点层就分开了，
/// 前端只是各自消费（ADR-0088 §2.3 双消费者）。
class RunTraceRepositoryImpl implements RunTraceRepository {
  RunTraceRepositoryImpl(this._network);

  final NetworkService _network;

  @override
  Future<List<RunTraceRun>> runs() async {
    final data = await _network.get('/ai/debug/conversations');
    return decodeList(data, RunTraceRun.fromJson);
  }

  @override
  Future<RunTraceDetail> detail(String runId) async {
    final data = await _network.get('/ai/debug/conversations/$runId');
    return RunTraceDetail.fromJson(decodeMap(data));
  }
}
