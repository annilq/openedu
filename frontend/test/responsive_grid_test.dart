import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/shared/widgets/responsive_grid.dart';

/// 回归守卫：工作台栅格在「竖向无界 + 宽屏并排」下不得抛布局异常。
///
/// 背景（实测）：工作台页面落在 `AppScrollPage` 的竖向滚动区，栅格拿到的高度约束是
/// `0<=h<=Infinity`。此时若用 `Row(crossAxisAlignment: stretch)` 做等高，RenderFlex
/// 会给子项下发 `tightFor(height: Infinity)` → 抛
/// 「BoxConstraints forces an infinite height」，整页崩。而普通 widget 测试默认在
/// 有界高度下 pump，测不出这个条件，故本测试显式复现竖向无界上下文。
void main() {
  testWidgets('宽屏并排在竖向无界上下文中不抛异常', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: AppResponsiveGrid(
                colsWide: 2,
                breakpoint: 400,
                children: const [
                  SizedBox(height: 120),
                  SizedBox(height: 240),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏退回单列且不抛异常', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: AppResponsiveGrid(
                colsWide: 2,
                breakpoint: 400,
                children: const [
                  SizedBox(height: 120),
                  SizedBox(height: 240),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
