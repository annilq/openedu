import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:kids_learn/shared/data/local/platform_speech_gateway.dart';
import 'package:kids_learn/shared/domain/voice_input.dart';

/// `SpeechToText()` 是**返回单例的 factory**，无法靠继承造假，所以用 mocktail。
class MockSpeechToText extends Mock implements SpeechToText {}

void main() {
  late MockSpeechToText speech;

  setUp(() {
    speech = MockSpeechToText();
  });

  PlatformSpeechGateway gateway() => PlatformSpeechGateway(speech: speech);

  void stubInitialize(Future<bool> Function() answer) {
    when(() => speech.initialize(
          onStatus: any(named: 'onStatus'),
          onError: any(named: 'onError'),
        )).thenAnswer((_) => answer());
  }

  Future<Object?> firstFailure(Duration silence) async {
    Object? failure;
    await expectLater(
      gateway().listen(silenceTimeout: silence),
      emitsError((error) {
        failure = error;
        return true;
      }),
    );
    return failure;
  }

  group('能力门禁（ADR-0063 §2）', () {
    test('initialize 成功 → ready', () async {
      stubInitialize(() async => true);
      expect(await gateway().probe(), VoiceAvailability.ready);
    });

    test('initialize 返回 false → denied（权限可恢复，麦按钮保留）', () async {
      stubInitialize(() async => false);
      expect(await gateway().probe(), VoiceAvailability.denied);
    });

    test('插件未实现的平台抛异常 → unsupported（麦按钮不渲染）', () async {
      // Linux 上 MethodChannel 无注册实现，调用是**抛** MissingPluginException，
      // 不是返回 false。不接住就会渲染出一个点了必然失败的按钮。
      when(() => speech.initialize(
            onStatus: any(named: 'onStatus'),
            onError: any(named: 'onError'),
          )).thenThrow(MissingPluginException('No implementation found'));
      expect(await gateway().probe(), VoiceAvailability.unsupported);
    });

    test('probe 结果被缓存，不重复探测', () async {
      stubInitialize(() async => true);
      final g = gateway();
      await g.probe();
      await g.probe();
      verify(() => speech.initialize(
            onStatus: any(named: 'onStatus'),
            onError: any(named: 'onError'),
          )).called(1);
    });
  });

  group('门禁未通过时 listen 不静默（ADR-0063 §2）', () {
    test('denied → 立刻失败，提示去系统设置', () async {
      stubInitialize(() async => false);
      final failure = await firstFailure(const Duration(seconds: 3));
      expect(failure, isA<VoiceInputFailure>());
      expect((failure! as VoiceInputFailure).message, contains('权限'));
    });

    test('unsupported → 立刻失败，提示是「平台不支持」而非「去设置」', () async {
      when(() => speech.initialize(
            onStatus: any(named: 'onStatus'),
            onError: any(named: 'onError'),
          )).thenThrow(MissingPluginException('No implementation found'));
      final failure = await firstFailure(const Duration(seconds: 3));
      expect((failure! as VoiceInputFailure).message, contains('不支持'));
    });
  });

  group('静默阈值按角色注入（ADR-0063 §6）', () {
    test('ready 时开始听，silenceTimeout 原样透传给 pauseFor', () async {
      stubInitialize(() async => true);
      final options = <SpeechListenOptions>[];
      when(() => speech.listen(
            onResult: any(named: 'onResult'),
            listenOptions: any(named: 'listenOptions'),
          )).thenAnswer((invocation) async {
        options.add(
            invocation.namedArguments[#listenOptions] as SpeechListenOptions);
      });

      // 学生端要放宽到 3s 以上：学生说「那个…三分之二…加…」停顿很多，
      // 平台默认 1–1.5s 会在句中掐断。
      gateway().listen(silenceTimeout: const Duration(seconds: 3));
      await pumpEventQueue();

      expect(options, hasLength(1));
      expect(options.single.pauseFor, const Duration(seconds: 3));
      expect(options.single.partialResults, isTrue);
    });
  });
}
