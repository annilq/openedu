import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kIsWeb;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../domain/voice_input.dart';

/// 平台原生 STT 实现（ADR-0063 §1 / §8）：**全工程唯一 import `speech_to_text` 的文件**。
///
/// 展示层只见 [VoiceInputPort]，不认识插件——这样换实现（例如日后在 Web 上改走
/// 后端自部署 ASR）不必动任何 UI。
class PlatformSpeechGateway implements VoiceInputPort {
  /// [speech] 可注入，仅用于测试：生产不传。
  PlatformSpeechGateway({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  VoiceAvailability? _availability;
  StreamController<VoiceTranscript>? _session;

  /// 单次会话的硬上限（ADR-0063 §4）。静音超时之外还要有总时长闸，
  /// 否则一直有环境噪声时会话会永远不结束。
  static const Duration maxListenFor = Duration(seconds: 60);

  @override
  Future<VoiceAvailability> probe() async {
    final cached = _availability;
    if (cached != null) return cached;
    return _availability = await _probeOnce();
  }

  Future<VoiceAvailability> _probeOnce() async {
    // Web 不做（ADR-0063 §3）：Chrome/Edge 把音频送 Google 云端，国内不可达。
    if (kIsWeb) {
      _log('probe → unsupported（Web 明确不做，ADR-0063 §3）');
      return VoiceAvailability.unsupported;
    }

    try {
      final ok = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
      );
      // initialize 返回 false「通常意味着用户拒绝了权限」，按插件文档即 [denied]。
      final availability =
          ok ? VoiceAvailability.ready : VoiceAvailability.denied;
      // 门禁结果决定麦按钮**出不出现**，而 unsupported 时界面上什么都不显示——
      // 少了这行日志，「按钮没出现」就完全无从归因（ADR-0063 §2 的静默失效风险）。
      _log('probe → $availability');
      return availability;
    } catch (error) {
      // Linux 等插件未实现的平台：MethodChannel 无注册实现，调用**抛**
      // MissingPluginException，而不是返回 false。不接住就判定不了门禁，
      // 后果是在 Linux 上渲染出一个点了必然失败的麦按钮。
      //
      // 另一种常见成因：跑的是**旧进程**。新增原生插件后 Hot Restart 不补原生
      // 注册，channel 调不通也走这条分支——此时完整重跑即可，不是代码问题。
      _log('probe → unsupported（插件不可用：$error）');
      return VoiceAvailability.unsupported;
    }
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[voice] $message');
  }

  @override
  Stream<VoiceTranscript> listen({required Duration silenceTimeout}) {
    _closeSession();
    final controller = StreamController<VoiceTranscript>();
    _session = controller;
    unawaited(_startSession(controller, silenceTimeout));
    return controller.stream;
  }

  Future<void> _startSession(
    StreamController<VoiceTranscript> controller,
    Duration silenceTimeout,
  ) async {
    final availability = await probe();
    if (availability != VoiceAvailability.ready) {
      _fail(
        controller,
        VoiceInputFailure(availability == VoiceAvailability.unsupported
            ? '当前平台不支持语音输入'
            : '麦克风权限未授权，请到系统设置中开启'),
      );
      return;
    }
    try {
      await _speech.listen(
        onResult: (result) => _emit(controller, result),
        listenOptions: SpeechListenOptions(
          // interim 结果要实时流入输入框（ADR-0063 §4）。
          partialResults: true,
          cancelOnError: true,
          // 静默多久算说完：儿童说话停顿多，阈值由调用方按角色注入（§6）。
          pauseFor: silenceTimeout,
          listenFor: maxListenFor,
          // 问句比指令长，用听写模式而不是默认的 confirmation。
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (error) {
      _fail(controller, VoiceInputFailure('$error'));
    }
  }

  @override
  Future<void> stop() async {
    if (_session == null) return;
    // 不在这里关流：stop 之后插件还会补一帧 final 结果，再由 `done` 状态收口。
    await _speech.stop();
  }

  @override
  Future<void> cancel() async {
    if (_session == null) return;
    await _speech.cancel();
    _closeSession();
  }

  void _emit(
      StreamController<VoiceTranscript> controller, SpeechRecognitionResult r) {
    if (controller.isClosed) return;
    controller.add(VoiceTranscript(text: r.recognizedWords, isFinal: r.finalResult));
  }

  void _onStatus(String status) {
    _log('status=$status');
    final controller = _session;
    if (controller == null || controller.isClosed) return;
    if (status == 'notListening' || status == 'done') {
      _closeSession();
    }
  }

  void _onError(SpeechRecognitionError error) {
    _log('error=${error.errorMsg} permanent=${error.permanent}');
    final controller = _session;
    if (controller == null || controller.isClosed) return;
    _fail(controller, VoiceInputFailure(error.errorMsg));
  }

  void _fail(StreamController<VoiceTranscript> controller,
      VoiceInputFailure failure) {
    _session = null;
    controller.addError(failure);
    unawaited(controller.close());
  }

  void _closeSession() {
    final controller = _session;
    if (controller == null) return;
    _session = null;
    unawaited(controller.close());
  }
}
