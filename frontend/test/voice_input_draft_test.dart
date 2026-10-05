// 守住 ADR-0063 §4 / §5 / §6 / §7 的几条契约：
//   ① 门禁 unsupported 时麦按钮根本不渲染（§2）；
//   ② 转写落草稿，**绝不自动发送**（§4）；
//   ③ 转写为空**不动输入框**，且必须提示（§4：不允许静默失败）；
//   ④ 「重说」清空草稿重新录制（§7）；
//   ⑤ 静默阈值按角色分档，儿童更宽（§6）；
//   ⑥ 移动端长按说话、桌面端点按切换（§5）。
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
import 'package:kids_learn/shared/widgets/app_voice_button.dart';

/// 假端口：按用例注入门禁结果与转写流，不碰任何平台通道。
class _FakeVoicePort implements VoiceInputPort {
  _FakeVoicePort(this.availability);

  final VoiceAvailability availability;

  /// 每次 `listen` 开一条新流——真实插件也是「一次会话一条流」，会话结束就关。
  StreamController<VoiceTranscript>? _active;
  StreamController<VoiceTranscript> get active => _active!;

  int startCount = 0;
  Duration? lastSilence;
  bool stopped = false;

  @override
  Future<VoiceAvailability> probe() async => availability;

  @override
  Stream<VoiceTranscript> listen({required Duration silenceTimeout}) {
    startCount++;
    lastSilence = silenceTimeout;
    _active = StreamController<VoiceTranscript>.broadcast();
    return active.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    // 真实插件在 stop 之后还会补一帧 final 结果，再由状态回调关流——这里照做，
    // 以免测试替身掩盖「提前关流丢最后一句」这类问题。
    active.add(const VoiceTranscript(text: '三分之二加五分之一', isFinal: true));
    unawaited(active.close());
  }

  @override
  Future<void> cancel() async {
    unawaited(active.close());
  }
}

class _Harness {
  _Harness(this.port, this.controller, this.sends);

  final _FakeVoicePort port;
  final TextEditingController controller;
  final List<String> sends;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required VoiceAvailability availability,
  AppUserMode mode = AppUserMode.child,
}) async {
  final port = _FakeVoicePort(availability);
  final controller = TextEditingController();
  final sends = <String>[];
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [voiceInputProvider.overrideWithValue(port)],
      // 必须显式传 theme：`ShadApp.custom` 不传会退回 shadcn 默认主题（ADR-0046
      // 记录过这个坑）。`appBuilder` 那条路径不会自动装 ShadToaster（只有传 `child`
      // 的 ShadAppBuilder 才会），所以这里显式包一层——否则 AppToast 直接抛
      // 「Could not find ShadToaster」。
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, mode, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: ShadToaster(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 420,
                  // UserModeScope 决定静音阈值档位，必须显式挂载：未挂载时
                  // `UserModeScope.of` 回退 parent，测儿童档会测错。
                  child: UserModeScope(
                    mode: mode,
                    child: AssistantInputBar(
                      controller: controller,
                      sending: false,
                      onSend: () => sends.add(controller.text),
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
  return _Harness(port, controller, sends);
}

/// 按下并等到长按生效，返回手势供调用方决定何时松手。
///
/// 测试里的默认平台是 Android，走的就是移动端「长按说话」这条主路径。
Future<TestGesture> _hold(WidgetTester tester) async {
  final gesture =
      await tester.startGesture(tester.getCenter(find.byType(AppVoiceButton)));
  await tester.pump(kLongPressTimeout);
  await tester.pumpAndSettle();
  return gesture;
}

void main() {
  testWidgets('门禁 unsupported 时麦按钮根本不渲染', (tester) async {
    await _pump(tester, availability: VoiceAvailability.unsupported);

    expect(find.byType(AppVoiceButton), findsNothing,
        reason: 'ADR-0063 §2：不可用时不渲染，而不是渲染一个禁用按钮');
    expect(find.byIcon(LucideIcons.mic), findsNothing);
  });

  testWidgets('长按说话：转写落草稿，绝不自动发送', (tester) async {
    final h = await _pump(tester, availability: VoiceAvailability.ready);
    expect(find.byType(AppVoiceButton), findsOneWidget);

    final gesture = await _hold(tester);
    expect(h.port.startCount, 1);

    // interim 结果是**整体替换**，不是追加（否则会叠出「三三三分之二」）。
    h.port.active.add(const VoiceTranscript(text: '三分之二', isFinal: false));
    await tester.pump();
    h.port.active
        .add(const VoiceTranscript(text: '三分之二加五分之一', isFinal: false));
    await tester.pump();

    expect(h.controller.text, '三分之二加五分之一');
    expect(h.sends, isEmpty,
        reason: 'ADR-0063 §4：ASR 错得离谱，自动发送会白烧一次模型往返');

    // 松手后仍是草稿状态，发送只能由用户触发。
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.port.stopped, isTrue);
    expect(h.sends, isEmpty);
  });

  testWidgets('转写为空不动输入框，且必须提示', (tester) async {
    final h = await _pump(tester, availability: VoiceAvailability.ready);
    h.controller.text = '我手打的问题';

    final gesture = await _hold(tester);
    // 一句话都没说就结束（静默超时 / 平台直接关流）。
    await h.port.active.close();
    await tester.pumpAndSettle();

    expect(h.controller.text, '我手打的问题', reason: '空转写不能冲掉输入框里已有的内容');
    expect(find.text('没听清，请再说一次'), findsOneWidget,
        reason: 'ADR-0063 §4：不允许静默失败');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('「重说」清空草稿并重新录制', (tester) async {
    final h = await _pump(tester, availability: VoiceAvailability.ready);

    final gesture = await _hold(tester);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.controller.text, '三分之二加五分之一');

    expect(find.text('重说'), findsOneWidget);
    await tester.tap(find.text('重说'));
    await tester.pumpAndSettle();

    expect(h.controller.text, isEmpty, reason: 'ADR-0063 §7：重说是整句重录，不是编辑');
    expect(h.port.startCount, 2);
  });

  testWidgets('静默阈值按角色分档：儿童更宽', (tester) async {
    final child = await _pump(tester, availability: VoiceAvailability.ready);
    final first = await _hold(tester);
    expect(child.port.lastSilence, VoiceSilence.child);
    await first.up();
    await tester.pumpAndSettle();

    final parent = await _pump(tester,
        availability: VoiceAvailability.ready, mode: AppUserMode.parent);
    final second = await _hold(tester);
    expect(parent.port.lastSilence, VoiceSilence.adult);
    await second.up();
    await tester.pumpAndSettle();

    expect(VoiceSilence.child, greaterThanOrEqualTo(const Duration(seconds: 3)),
        reason: 'ADR-0063 §6：儿童档不得窄于 3s');
  });

  testWidgets('权限被拒时按钮仍在，点击给出引导', (tester) async {
    await _pump(tester, availability: VoiceAvailability.denied);

    expect(find.byType(AppVoiceButton), findsOneWidget,
        reason: 'denied 是可恢复状态，按钮消失会让人以为没有这个功能');
    final gesture = await _hold(tester);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.textContaining('麦克风权限未授权'), findsOneWidget);
  });

  testWidgets('桌面档点按切换：一次点击起、再一次停', (tester) async {
    var listening = false;
    var starts = 0;
    var stops = 0;
    await tester.pumpWidget(
      ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              // 组件是受控的：[AppVoiceButton] 不自己记住「在不在录」，所以这里必须
              // 把 listening 回灌进去，否则第二次点击仍会走 onStart。
              child: StatefulBuilder(
                builder: (context, setState) => AppVoiceButton(
                  visible: true,
                  listening: listening,
                  holdToTalk: false,
                  onStart: () => setState(() {
                    starts++;
                    listening = true;
                  }),
                  onStop: () => setState(() {
                    stops++;
                    listening = false;
                  }),
                  onCancel: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppVoiceButton));
    await tester.pumpAndSettle();
    expect(starts, 1, reason: 'ADR-0063 §5：桌面端点按即开始');

    await tester.tap(find.byType(AppVoiceButton));
    await tester.pumpAndSettle();
    expect(stops, 1, reason: '再点一次结束');
    expect(starts, 1);
  });
}
