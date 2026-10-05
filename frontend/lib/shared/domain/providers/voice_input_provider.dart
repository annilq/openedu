import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/platform_speech_gateway.dart';
import '../voice_input.dart';

/// 语音输入的**组合根**（ADR-0063 §8）。
///
/// 展示层只认 [VoiceInputPort] 这个领域端口，不 import `data/`——
/// R4 棘轮（`presentation/` 不得 import `*/data/`）由此成立，换实现也不动 UI。
final voiceInputProvider = Provider<VoiceInputPort>((ref) {
  return PlatformSpeechGateway();
});
