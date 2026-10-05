import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
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
    if (kIsWeb) return VoiceAvailability.unsupported;

    try {
      final ok = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
      );
      // initialize 返回 false「通常意味着用户拒绝了权限」，按插件文档即 [denied]。
      return ok ? VoiceAvailability.ready : VoiceAvailability.denied;
    } catch (_) {
      // Linux 等插件未实现的平台：MethodChannel 无注册实现，调用**抛**
      // MissingPluginException，而不是返回 false。不接住就判定不了门禁，
      // 后果是在 Linux 上渲染出一个点了必然失败的麦按钮。
      return VoiceAvailability.unsupported;
    }
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
    final controller = _session;
    if (controller == null || controller.isClosed) return;
    if (status == 'notListening' || status == 'done') {
      _closeSession();
    }
  }

  void _onError(SpeechRecognitionError error) {
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
