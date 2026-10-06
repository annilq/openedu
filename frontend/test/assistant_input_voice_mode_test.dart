// 守住 ADR-0063 §5 的「微信式两态切换」契约：
//   ① 默认键盘态：输入框在、切换按钮显示键盘图标、没有「按住 说话」；
//   ② 点切换按钮 → 语音态：输入区整体换成「按住 说话」，图标换成麦；
//   ③ 语音态下**长按**才录音，不是点一下就开始；
//   ④ 转写内容直接显示在「按住 说话」这条上，不必切回键盘才看得到；
//   ⑤ 再点一次回到键盘态，转写内容仍在输入框里；
//   ⑥ 门禁不放行时两个图标都不渲染。
//
// ⚠️ 树里**不套 Material**：App 根是 `ShadApp` + `CupertinoApp`，整棵树没有 Material
// 祖先，任何 Material 系控件会在构建期直接崩（真机才炸、analyze 照不出）。
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/presentation/widgets/assistant_input_bar.dart';
import 'package:kids_learn/shared/domain/providers/voice_input_provider.dart';
import 'package:kids_learn/shared/domain/voice_input.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_actions.dart';
import 'package:kids_learn/shared/widgets/app_voice_button.dart';

/// 假端口：按用例注入门禁结果与转写流，不碰任何平台通道。
class _FakeVoicePort implements VoiceInputPort {
  _FakeVoicePort(this.availability);

  final VoiceAvailability availability;

  StreamController<VoiceTranscript>? _active;
  StreamController<VoiceTranscript> get active => _active!;

  int startCount = 0;
  bool stopped = false;

  @override
  Future<VoiceAvailability> probe() async => availability;

  @override
  Stream<VoiceTranscript> listen({required Duration silenceTimeout}) {
    startCount++;
    _active = StreamController<VoiceTranscript>.broadcast();
    return active.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    active.add(const VoiceTranscript(text: '三分之二加五分之一', isFinal: true));
    unawaited(active.close());
  }

  @override
  Future<void> cancel() async {
    unawaited(active.close());
  }
}

class _Harness {
  _Harness(this.port, this.controller);

  final _FakeVoicePort port;
  final TextEditingController controller;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required VoiceAvailability availability,
}) async {
  final port = _FakeVoicePort(availability);
  final controller = TextEditingController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    // ⚠️ 每个用例都用新的 key：`tester.pumpWidget` 会复用同类型、同位置的 element，
    // 上一用例的 `_voiceMode` 会漏到下一用例（表现为切换按钮找不到）。
    ProviderScope(
      key: UniqueKey(),
      overrides: [voiceInputProvider.overrideWithValue(port)],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.child, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: ShadToaster(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 420,
                  child: UserModeScope(
                    mode: AppUserMode.child,
                    child: AssistantInputBar(
                      controller: controller,
                      sending: false,
                      onSend: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(port, controller);
}

/// 切到语音态：点一次模式切换按钮。
///
/// 用 [AppIconAction] 定位而不是 `byIcon(LucideIcons.mic)`：语音态下树里有两个麦图标
/// （「按住 说话」条上有一个，切换按钮本身也是一个），按图标找会歧义。
Future<void> _enterVoiceMode(WidgetTester tester) async {
  await tester.tap(find.byType(AppIconAction));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认键盘态：输入框在，没有「按住 说话」', (tester) async {
    await _pump(tester, availability: VoiceAvailability.ready);

    expect(find.byType(ShadInput), findsOneWidget);
    expect(find.byIcon(LucideIcons.keyboard), findsOneWidget,
        reason: '默认态的切换按钮显示键盘图标，表示「当前是键盘输入」');
    expect(find.text(AppVoiceButton.idleLabel), findsNothing,
        reason: 'ADR-0063 §5：语音输入要先切模式，不能常驻抢键盘的位置');
  });

  testWidgets('点切换按钮 → 输入区整体变成「按住 说话」', (tester) async {
    await _pump(tester, availability: VoiceAvailability.ready);

    await _enterVoiceMode(tester);

    expect(find.byType(ShadInput), findsNothing,
        reason: '语音态下输入框整个被「按住 说话」取代，两者不并存');
    expect(find.text(AppVoiceButton.idleLabel), findsOneWidget);
    expect(find.byIcon(LucideIcons.mic), findsWidgets,
        reason: '切过去之后图标表示当前是语音态');
  });

  testWidgets('语音态下长按才录音：转写显示在这条上，不自动发送', (tester) async {
    final h = await _pump(tester, availability: VoiceAvailability.ready);
    await _enterVoiceMode(tester);

    // 只点一下不算录音（微信式：误触不该开口）。
    await tester.tap(find.byType(AppVoiceButton));
    await tester.pumpAndSettle();
    expect(h.port.startCount, 0,
        reason: '桌面档才点按即说；触屏档的长按手势不应被 tap 抢先触发');

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(AppVoiceButton)));
    await tester.pump(kLongPressTimeout);
    await tester.pumpAndSettle();

    expect(h.port.startCount, 1);
    expect(find.text(AppVoiceButton.listeningLabel), findsOneWidget,
        reason: '录音中必须给出「松开 完成」的反馈，否则用户不知道有没有按住');

    h.port.active.add(const VoiceTranscript(text: '三分之二', isFinal: false));
    await tester.pumpAndSettle();
    expect(find.text('三分之二'), findsOneWidget,
        reason: '转写直接显示在按钮上，用户不必切回键盘才知道听到了什么');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.port.stopped, isTrue);
    expect(h.controller.text, '三分之二加五分之一');
  });

  testWidgets('再点一次回到键盘态，转写内容仍在输入框里', (tester) async {
    final h = await _pump(tester, availability: VoiceAvailability.ready);
    await _enterVoiceMode(tester);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(AppVoiceButton)));
    await tester.pump(kLongPressTimeout);
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppIconAction));
    await tester.pumpAndSettle();

    expect(find.byType(ShadInput), findsOneWidget);
    expect(find.text(AppVoiceButton.idleLabel), findsNothing);
    expect(h.controller.text, '三分之二加五分之一',
        reason: '切换模式不丢草稿——转写只有一份，写在输入框里（ADR-0063 §4）');
  });

  testWidgets('门禁 unsupported 时切换按钮根本不渲染', (tester) async {
    await _pump(tester, availability: VoiceAvailability.unsupported);

    expect(find.byIcon(LucideIcons.keyboard), findsNothing);
    expect(find.byIcon(LucideIcons.mic), findsNothing);
    expect(find.text(AppVoiceButton.idleLabel), findsNothing);
    expect(find.byType(ShadInput), findsOneWidget,
        reason: '没有语音也不该把键盘输入弄丢');
  });
}
