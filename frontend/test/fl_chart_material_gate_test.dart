import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';

/// fl_chart 落地前的强制 gate（ADR-0075 §2.3）。
///
/// 本工程禁用 Material 控件、根树是 ShadApp + CupertinoApp、无 Material 祖先；
/// 任何 Material widget（如 `Tooltip` / `Material`）在构建期即抛
/// 「No Material widget found」并在 CI 阻断。fl_chart 内部若引用了 Material widget，
/// 本测试会在**非 Material** 根树（裸 `CupertinoApp`）下构建环形图与条形图时抛异常，
/// 从而立刻暴露——先于任何业务页接入。
///
/// 这是后续所有图表 ticket（02 适配器层 / 03 速览层 / 04 分析层）的前置护栏：
/// 若本测试失败，说明 fl_chart 版本与「无 Material 祖先」约束不兼容，必须换方案，
/// 不得带病推进。
void main() {
  testWidgets('fl_chart 环形图可在无 Material 祖先的树中构建', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 220,
            height: 180,
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(value: 3, color: Color(0xFF2F6FD0), radius: 40),
                  PieChartSectionData(value: 1, color: Color(0xFFFF6B5A), radius: 40),
                ],
                centerSpaceRadius: 36,
                sectionsSpace: 2,
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'fl_chart 内部不得引用 Material widget，否则无 Material 祖先时构建期抛'
          '「No Material widget found」（ADR-0075 §2.3 强制 gate）。',
    );
    expect(find.byType(PieChart), findsOneWidget);
  });

  testWidgets('fl_chart 条形图可在无 Material 祖先的树中构建', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 220,
            height:180,
            child: BarChart(
              BarChartData(
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [
                    BarChartRodData(toY: 3, width: 16, color: Color(0xFF2F6FD0)),
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(toY: 1, width: 16, color: Color(0xFFFF6B5A)),
                  ]),
                ],
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'fl_chart 内部不得引用 Material widget，否则无 Material 祖先时构建期抛'
          '「No Material widget found」（ADR-0075 §2.3 强制 gate）。',
    );
    expect(find.byType(BarChart), findsOneWidget);
  });
}
