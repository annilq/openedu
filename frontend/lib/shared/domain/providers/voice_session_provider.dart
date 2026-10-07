import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../voice_input.dart';
import 'voice_input_provider.dart';

/// 一次语音输入会话的运行时状态（ADR-0063 §4）。
///
/// 状态链固定为「麦按钮 → 实时转写 → 停止 → 落草稿 → 用户发送」：**这里从不发送**。
/// 中文数学术语 ASR 错得离谱（三分之二 / 方程 / π），自动发送会白烧一次模型往返且
/// 答非所问——对「AI 老师」的信任是一次性损耗。
class VoiceSessionState {
  const VoiceSessionState({
    this.availability,
    this.listening = false,
    this.draft = '',
    this.failure,
    this.spoken = false,
  });

  /// 门禁探测结果。`null` = 尚未探测完——此时麦按钮**不渲染**，等结果出来再出现，
  /// 避免「先出现再消失」的跳变。
  final VoiceAvailability? availability;

  final bool listening;

  /// 当前应写进输入框的**整段**文本（不是增量片段）。
  ///
  /// interim 结果会整体替换前一条（否则会叠出「三三三分之二」），消费方应当用它
  /// 覆盖输入框，而不是追加。
  final String draft;

  /// 本次会话的失败原因。非空时调用方须提示（ADR-0063 §4：不允许静默失败）。
  final VoiceInputFailure? failure;

  /// 本次会话是否**真的转写出过内容**。
  ///
  /// 与 [draft] 非空不是一回事：[draft] 在会话开始时就被填成 [VoiceSession.start]
  /// 传入的 baseText（用户可能先打了半句），只有收到非空转写才置真。「重说」挂在这个
  /// 标记上，否则会把用户手打的半句一并清掉。
  final bool spoken;

  /// 麦按钮是否该出现（ADR-0063 §2）。
  ///
  /// [VoiceAvailability.denied] 也算可见：权限是可恢复的，按钮消失反而让人以为
  /// 没有这个功能；点了以后由 [VoiceSession.start] 产出引导去系统设置的失败原因。
  bool get voiceVisible =>
      availability == VoiceAvailability.ready ||
      availability == VoiceAvailability.denied;

  VoiceSessionState copyWith({
    VoiceAvailability? availability,
    bool? listening,
    String? draft,
    VoiceInputFailure? failure,
    bool? spoken,
    bool clearFailure = false,
  }) {
    return VoiceSessionState(
      availability: availability ?? this.availability,
      listening: listening ?? this.listening,
      draft: draft ?? this.draft,
      failure: clearFailure ? null : (failure ?? this.failure),
      spoken: spoken ?? this.spoken,
    );
  }
}

/// 语音会话的状态机：把 [VoiceInputPort] 的流收成 [VoiceSessionState]。
///
/// 放在 `domain/providers/` 而不是 widget 里，是因为「转写为空要提示」「停止后要
/// 判定有没有说过话」这些规则属于契约而非画法，且要能脱离 UI 测。
class VoiceSession extends StateNotifier<VoiceSessionState> {
  VoiceSession(this._port) : super(const VoiceSessionState()) {
    // 启动时探测一次（ADR-0063 §2）。结果由网关缓存，重挂载几乎零成本。
    unawaited(probe());
  }

  final VoiceInputPort _port;

  StreamSubscription<VoiceTranscript>? _sub;
  bool _cancelled = false;
  bool _heardSomething = false;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> probe() async {
    if (state.availability != null) return;
    final availability = await _port.probe();
    if (!mounted) return;
    state = state.copyWith(availability: availability);
  }

  /// 开始听。[baseText] 是开始前输入框已有的文本，转写结果**接在它后面**，
  /// 避免用户先打了半句再说话时把已有内容冲掉。
  Future<void> start({
    String baseText = '',
    required Duration silenceTimeout,
  }) async {
    if (state.listening) return;
    final availability = await _port.probe();
    if (!mounted) return;

    if (availability != VoiceAvailability.ready) {
      // 门禁未过：给失败原因，让调用方提示。不是静默返回——静默失败是这个功能
      // 最大的风险（ADR-0063 §2）。
      state = state.copyWith(
        availability: availability,
        listening: false,
        failure: VoiceInputFailure(
          availability == VoiceAvailability.unsupported
              ? '当前平台不支持语音输入'
              : '麦克风权限未授权，请到系统设置中开启',
        ),
        clearFailure: false,
      );
      return;
    }

    _cancelled = false;
    _heardSomething = false;
    state = state.copyWith(
      availability: availability,
      listening: true,
      draft: baseText,
      spoken: false,
      clearFailure: true,
    );

    _sub = _port.listen(silenceTimeout: silenceTimeout).listen(
      (transcript) {
        _heardSomething |= transcript.text.trim().isNotEmpty;
        if (!mounted) return;
        state = state.copyWith(
          draft: _join(baseText, transcript.text),
          spoken: _heardSomething,
        );
      },
      // cancelOnError：出错后不会再走 onDone，避免错误与「没听清」两条提示叠着出。
      cancelOnError: true,
      onError: (Object error) {
        _finish(error is VoiceInputFailure
            ? error
            : VoiceInputFailure(error.toString()));
      },
      onDone: () {
        _finish(_cancelled || _heardSomething
            ? null
            : const VoiceInputFailure('没听清，请再说一次'));
      },
    );
  }

  /// 松手 / 再点一次：停止并等待平台补一帧 final 结果。
  Future<void> stop() async {
    if (!state.listening) return;
    await _port.stop();
  }

  /// 上滑取消 / 放弃本次：丢弃结果，不产生「没听清」提示。
  Future<void> cancel() async {
    if (!state.listening) return;
    _cancelled = true;
    // 订阅**就地断开**，不等 [_port.cancel()] 回来：平台的 cancel 是异步的，在它
    // 返回之前仍可能补一帧 final 结果写进草稿——而调用方（比如点发送）正是靠
    // 「不会再有后续写入」来保证输入框内容稳定的。
    _sub?.cancel();
    _sub = null;
    await _port.cancel();
    _finish(null);
  }

  /// 发送后清空草稿：否则「重说」会挂在上一条已发走的文本上。
  void clearDraft() {
    state = state.copyWith(draft: '', spoken: false, clearFailure: true);
  }

  void _finish(VoiceInputFailure? failure) {
    _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    state = state.copyWith(
      listening: false,
      failure: failure,
      clearFailure: failure == null,
    );
  }

  static String _join(String base, String spoken) {
    final head = base.trimRight();
    final tail = spoken.trimLeft();
    if (head.isEmpty) return tail;
    if (tail.isEmpty) return head;
    return '$head $tail';
  }
}

/// 语音会话状态。`autoDispose`：随输入栏卸载而销毁，不留跨页面的残留录音态。
final voiceSessionProvider =
    StateNotifierProvider.autoDispose<VoiceSession, VoiceSessionState>((ref) {
  return VoiceSession(ref.watch(voiceInputProvider));
});
