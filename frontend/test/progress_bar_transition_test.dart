import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';

/// 进度条的**值过渡**守卫。
///
/// `ShadProgress` 的 determinate 分支是裸 `FractionallySizedBox`
/// （`shadcn_ui/src/components/progress.dart`，内部零动画），直接换 `value`
/// 条子就硬跳。而「答完一题，掌握度条长出来」是这个 App 里进步信号最强的时刻——
/// 硬跳等于把信号本身丢掉（本条即 P1-4）。
///
/// 量的是填充条的 `widthFactor`（占轨道的比例）而不是像素宽：像素宽随测试视口
/// 变化，把它焊进断言，测试就变成在测视口尺寸。
///
/// **为什么必须守着**：把 `TweenAnimationBuilder` 去掉之后条子照常显示正确的
/// 百分比，截图看不出来、`flutter analyze` 也不会响——只有「中途量一次」会红。
void main() {
  testWidgets('value 变化走隐式过渡，不硬跳', (tester) async {
    await tester.pumpWidget(_host(0.2));
    expect(_fill(tester), 0.2, reason: '首次挂载应直接落在终值，不该从 0 扫一遍');

    await tester.pumpWidget(_host(1.0));
    await tester.pump(); // 起跳
    await tester.pump(AppMotion.state ~/ 2);

    final mid = _fill(tester);
    expect(mid, greaterThan(0.2),
        reason: '值变大后条子一点没动——过渡没生效，退回了 ShadProgress 的硬跳。');
    expect(mid, lessThan(1.0),
        reason: '值一变就到终值，说明过渡根本不存在。');

    await tester.pumpAndSettle();
    expect(_fill(tester), 1.0, reason: '过渡必须收敛到终值，不能停在中间。');
  });

  testWidgets('值变小时同样过渡（回退方向也要有）', (tester) async {
    await tester.pumpWidget(_host(1.0));
    await tester.pumpWidget(_host(0.4));
    await tester.pump();
    await tester.pump(AppMotion.state ~/ 2);

    final mid = _fill(tester);
    expect(mid, lessThan(1.0));
    expect(mid, greaterThan(0.4));

    await tester.pumpAndSettle();
    expect(_fill(tester), 0.4);
  });

  testWidgets('系统开启「减弱动态效果」时不补过渡，直接落终值', (tester) async {
    await tester.pumpWidget(_host(0.2, reduceMotion: true));
    expect(_fill(tester), 0.2);

    await tester.pumpWidget(_host(1.0, reduceMotion: true));
    expect(_fill(tester), 1.0,
        reason: '隐式动画不自动尊重系统设置——调用点必须显式读 reducedMotionOf(context)，'
            '否则「减弱动态效果」形同虚设。');
  });
}

/// 读取进度条填充占轨道的比例。
double _fill(WidgetTester tester) {
  final box = tester.widget<FractionallySizedBox>(find.descendant(
    of: find.byType(AppProgressBar),
    matching: find.byType(FractionallySizedBox),
  ));
  return box.widthFactor!;
}

/// 宿主：显式传 `theme:`——`ShadApp.custom` 不传会退回 shadcn 默认主题，
/// 量到的颜色/内边距都不是产品的值。
///
/// reduce-motion 通过**包一层 MediaQuery** 注入（`copyWith` 保留 size 等字段，
/// 直接 `MediaQueryData(disableAnimations: true)` 会把 size 变成 Size.zero）。
Widget _host(double value, {bool reduceMotion = false}) => ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
      appBuilder: (_) => CupertinoApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: Center(child: AppProgressBar(value: value)),
          ),
        ),
      ),
    );
