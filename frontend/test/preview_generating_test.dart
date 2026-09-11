import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/features/home/presentation/widgets/parent/preview_generating.dart';

/// 抓「推理闪现」回归：渲染层必须忠实映射 [reasoning]，给定即同步显示全文，
/// 不得依赖自定时 Timer（旧 [ReasoningTypewriterWidget] 在生成期 `_shown` 永不前进，
/// 题卡到达后全文闪现）。widget 测试中不 advance 任何 Timer，故本测试在旧实现下必失败。
Widget _host(Widget child) => CupertinoApp(home: CupertinoPageScaffold(child: child));

void main() {
  testWidgets('推理给定即同步显示全文（含光标），不依赖定时器', (tester) async {
    await tester.pumpWidget(
      _host(const PreviewGenerating(
        index: 1,
        label: '',
        reasoning: '先审题再拆解考点',
        streaming: true,
      )),
    );
    // 同步断言：屏幕上应立即可见完整推理 + 光标，不应停留在占位/空。
    expect(find.text('先审题再拆解考点▌'), findsOneWidget);
    expect(find.text('正在构思出题思路…'), findsNothing);
  });

  testWidgets('streaming=false 时不挂光标', (tester) async {
    await tester.pumpWidget(
      _host(const PreviewGenerating(
        index: 2,
        label: '已生成',
        reasoning: '已完成解析',
        streaming: false,
      )),
    );
    expect(find.text('已完成解析'), findsOneWidget);
    expect(find.text('已完成解析▌'), findsNothing);
  });

  testWidgets('reasoning 为空时显示占位文案', (tester) async {
    await tester.pumpWidget(
      _host(const PreviewGenerating(
        index: 3,
        label: '',
        reasoning: '',
        streaming: true,
      )),
    );
    expect(find.text('正在构思出题思路…'), findsOneWidget);
  });
}
