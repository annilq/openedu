import '../run_trace.dart';

/// 运行轨迹端口（ADR-0088 ticket 02）：只读「全步骤 + 元数据」口径。
///
/// 与 [AssistantRepository]（会话历史的气泡口径）是**两个并列消费者**，刻意分开
/// 成两个端口而不是在既有端口上加方法：混在一起，两种口径的演进会互相绊住——
/// 气泡投影加字段时不必惊动轨迹页，轨迹页要步级 usage 时也不必拖着气泡载荷变重。
abstract class RunTraceRepository {
  /// 运行列表（时间倒序）。教师看自家、admin 看全部——范围由服务端按角色钉死。
  Future<List<RunTraceRun>> runs();

  /// 一次运行的全部步骤（按 turn 正序）。越权由服务端拒（403）。
  Future<RunTraceDetail> detail(String runId);
}
