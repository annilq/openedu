/// 语音输入的领域契约（ADR-0063）。
///
/// 这里是**纯 Dart**：不 import 任何插件、不碰平台通道。平台实现在
/// `shared/data/local/platform_speech_gateway.dart`，展示层只认本文件的端口。
library;

/// 语音能力门禁的三态（ADR-0063 §2）。
///
/// 门禁在启动时探测一次，UI 按三态分叉：
/// - [ready]：麦按钮常驻输入框；
/// - [denied]：麦按钮**保留**（权限可恢复），点击后引导去系统设置；
/// - [unsupported]：麦按钮**根本不渲染**，不留占位、不留空隙。
///
/// 为什么 [unsupported] 要「不渲染」而不是「渲染一个禁用按钮」：禁用的麦克风图标
/// 会让人反复点它，把「这个平台没有语音」变成「这个 App 坏了」。
enum VoiceAvailability {
  /// 平台原生 STT 可用且已授权。
  ready,

  /// 平台有这个能力，但麦克风 / 语音识别授权被拒。
  denied,

  /// 该平台没有可用的平台原生 STT（Linux / Web，见 ADR-0063 §3）。
  unsupported,
}

/// 一次转写结果。
///
/// [isFinal] 为 false 的是 interim 结果——它会持续被同一次会话的后续结果**整体替换**，
/// 消费方应当「用最新一条覆盖草稿」，而不是逐条拼接（否则会叠出「三三三分之二」）。
class VoiceTranscript {
  const VoiceTranscript({required this.text, required this.isFinal});

  /// 截至当前的整段转写文本（不是增量片段）。
  final String text;

  /// 是否为本次会话的最终结果。
  final bool isFinal;

  bool get isEmpty => text.trim().isEmpty;
}

/// 语音输入失败（ADR-0063 §4）：转写会话因错误提前结束。
///
/// 刻意不暴露插件的错误类型——展示层不需要知道底层是 Android 还是 iOS 的实现。
class VoiceInputFailure implements Exception {
  const VoiceInputFailure(this.message);

  final String message;

  @override
  String toString() => 'VoiceInputFailure: $message';
}

/// 语音输入端口：把「说的话」变成文本，仅此而已（ADR-0063 §1）。
///
/// 产物是普通文本，经输入框进入 `assistantNotifierProvider` 后与手打文本完全同权——
/// 后续走的仍是 `POST /api/v1/assistant/chat` 唯一链路，协议零改动。
abstract class VoiceInputPort {
  /// 探测一次语音能力。可反复调用，实现应缓存结果。
  Future<VoiceAvailability> probe();

  /// 开始听，转写结果以流返回（含 interim）。
  ///
  /// [silenceTimeout] 是「静默多久算说完」。**必须按角色注入**：成人沿用平台默认
  /// （约 1–1.5s），儿童要放宽到 3s 以上——孩子说「那个…三分之二…加…五分之一…」
  /// 中间停顿很多，默认阈值会在句中掐断（ADR-0063 §6）。
  ///
  /// 流在以下任一情况关闭：调用 [stop] / [cancel]、静默超时、平台错误。
  /// 若门禁不是 [VoiceAvailability.ready]，流立刻以 [VoiceInputFailure] 结束。
  Stream<VoiceTranscript> listen({required Duration silenceTimeout});

  /// 停止并等待最终结果（对应「松手 / 再点一次」）。
  Future<void> stop();

  /// 丢弃本次结果（对应「上滑取消 / 重说」）。
  Future<void> cancel();
}
