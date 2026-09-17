import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/presentation/provider/assistant_notifier.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_message_list.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 「思考中」阶段文案**切换**的过渡守卫（P2-3）。
///
/// 阶段文案不是「第一次出现」而是**反复被改写**：一次问答里路由帧、每个工具调用帧
/// 都会替换它（「正在检索错题」→「正在汇总」）。直接换文本是硬切，而硬切恰恰把
/// 「又推进了一步」读成了闪烁——这正是要有的那个信号，不能丢。
///
/// 判据是「过渡期间新旧文案**同时**在树上」：`AnimatedSwitcher` 靠 key 判别换了
/// 孩子，把 key 写成 `const` 会让整段过渡静默失效，而屏幕上只是「换得干脆了点」。
///
/// **不用 `pumpAndSettle`**：这个气泡里挂着不确定态的 `CircularProgressIndicator`，
/// 它永远排下一帧，settle 必然超时。
void main() {
  testWidgets('阶段文案切换时新旧同时在场（说明走的是过渡）', (tester) async {
    await tester.pumpWidget(_host([_thinking('正在检索错题')]));
    expect(find.text('正在检索错题'), findsOneWidget);

    await tester.pumpWidget(_host([_thinking('正在汇总')]));
    await tester.pump();

    expect(find.text('正在检索错题'), findsOneWidget,
        reason: '旧文案已经不在树上——阶段切换是硬切，没有过渡。');
    expect(find.text('正在汇总'), findsOneWidget);

    // 退场是「逆向跑完同一档时长 + 再排一帧摘掉旧节点」，且计时器要等第一次
    // tick 才开始计时。所以这里推两档时长——断言的是「会收敛」，不是「第几帧」；
    // 写死单档时长会把测试绑在帧调度细节上。
    await tester.pump(AppMotion.state);
    await tester.pump(AppMotion.state);
    await tester.pump();

    expect(find.text('正在检索错题'), findsNothing,
        reason: '过渡结束后旧文案必须退场，不能叠着不走。');
    expect(find.text('正在汇总'), findsOneWidget);
  });

  testWidgets('系统开启「减弱动态效果」时阶段切换即时完成', (tester) async {
    await tester.pumpWidget(_host([_thinking('正在检索错题')], reduceMotion: true));

    await tester.pumpWidget(_host([_thinking('正在汇总')], reduceMotion: true));
    await tester.pump();
    await tester.pump();

    expect(find.text('正在检索错题'), findsNothing,
        reason: 'reduce-motion 下不该还留着旧文案淡出（隐式/显式过渡都必须显式读 '
            'reducedMotionOf，系统设置不会自动生效）。');
    expect(find.text('正在汇总'), findsOneWidget);
  });

  testWidgets('阶段为空时回落默认文案', (tester) async {
    await tester.pumpWidget(_host([_thinking('')]));
    expect(find.text('思考中…'), findsOneWidget);
  });
}

AssistantMessage _thinking(String stage) =>
    AssistantMessage(role: 'ai', thinking: true, stage: stage);

Widget _host(List<AssistantMessage> messages, {bool reduceMotion = false}) =>
    ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
      appBuilder: (_) => CupertinoApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            // ListView 需要确定高度，否则在无界约束下直接抛。
            child: SizedBox(
              height: 400,
              child: AssistantMessageList(messages: messages),
            ),
          ),
        ),
      ),
    );
