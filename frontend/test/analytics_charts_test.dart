import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kids_learn/shared/widgets/analytics_charts.dart';

/// 图表适配器层测试（ticket 02，ADR-0075 §2.3）。
///
/// 两张关注点：
///  1. **行为**：四个适配器在**非 Material** 根树（裸 CupertinoApp）下都能构建，
///     且自定义横向条的点击钻取回调真的触发；环形中心文案渲染。
///  2. **护栏**：全仓只有 `analytics_charts.dart` 能 import / 裸用 fl_chart 的
///     `BarChart` / `PieChart`——业务页必须经适配器，不得绕过（否则风格漂移）。
///     两个探测器都做了精度处理：裸用探测按**词边界**匹配（否则被适配器类名
///     `AppBarChart(` 里的子串误伤），import 探测**引号不敏感**。
void main() {
  Widget wrap(Widget child, {Brightness b = Brightness.light}) => CupertinoApp(
        theme: CupertinoThemeData(brightness: b),
        home: Center(child: child),
      );

  testWidgets('AppDonutChart 渲染环形 + 中心文案，无 Material 异常', (tester) async {
    await tester.pumpWidget(
      wrap(
        AppDonutChart(
          segments: const [
            DonutSegment(value: 3, color: Color(0xFF2F6FD0)),
            DonutSegment(value: 1, color: Color(0xFFFF6B5A)),
          ],
          centerTop: '12',
          centerBottom: '已掌握',
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: '非 Material 树中不得抛「No Material widget found」');
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('已掌握'), findsOneWidget);
  });

  testWidgets('AppDonutChart 暗色模式令牌读取不崩', (tester) async {
    await tester.pumpWidget(
      wrap(
        AppDonutChart(
          segments: const [
            DonutSegment(value: 2, color: Color(0xFF2F6FD0)),
          ],
          centerTop: '1',
        ),
        b: Brightness.dark,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppGroupedBarChart 渲染分组条，无 Material 异常', (tester) async {
    await tester.pumpWidget(
      wrap(
        AppGroupedBarChart(
          data: const [
            GroupedBarDatum(label: '数学', series: [
              BarSeries(name: '练习', value: 80, color: Color(0xFF2F6FD0)),
              BarSeries(name: '复习', value: 60, color: Color(0xFFFF6B5A)),
            ]),
            GroupedBarDatum(label: '语文', series: [
              BarSeries(name: '练习', value: 70, color: Color(0xFF2F6FD0)),
              BarSeries(name: '复习', value: 40, color: Color(0xFFFF6B5A)),
            ]),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('AppStackedBarChart 渲染堆叠条，无 Material 异常', (tester) async {
    await tester.pumpWidget(
      wrap(
        AppStackedBarChart(
          data: const [
            StackedBarDatum(label: '数学', segments: [
              StackedSegment(name: '活跃', value: 30, color: Color(0xFFFF6B5A)),
              StackedSegment(name: '毕业', value: 10, color: Color(0xFF2B9348)),
            ]),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('AppBarChart 横向条渲染 + 点击钻取回调触发', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      wrap(
        AppBarChart(
          data: const [
            BarDatum(label: 'KP A', value: 12, color: Color(0xFFFF6B5A)),
            BarDatum(label: 'KP B', value: 5, color: Color(0xFF2F6FD0)),
          ],
          onTap: (i) => tapped = i,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('KP A'), findsOneWidget);

    await tester.tap(find.text('KP A'));
    await tester.pump();
    expect(tapped, 0, reason: '横向条点击应触发钻取回调并带回正确下标');
  });

  testWidgets('AppBarChart 无 onTap 时不包裹可点区', (tester) async {
    await tester.pumpWidget(
      wrap(
        const AppBarChart(
          data: [BarDatum(label: 'X', value: 1, color: Color(0xFF2F6FD0))],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('X'), findsOneWidget);
  });

  test('护栏：全仓只有适配器 import / 裸用 fl_chart（ADR-0075 §2.3）', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: '请在 frontend/ 目录下运行（flutter test 的 CWD 应为 frontend/）');

    final sources = <String, String>{};
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll(r'\', '/').split('lib/').last;
      sources[rel] = entity.readAsStringSync();
    }

    expect(flChartImporters(sources), ['shared/widgets/analytics_charts.dart'],
        reason: '只有 analytics_charts.dart 允许 import fl_chart，业务页必须走适配器。');
    final bareUsers = bareFlChartUsers(sources);
    expect(bareUsers, isEmpty,
        reason: '以下文件裸用了 fl_chart 图表：$bareUsers（应改为经适配器）。');
  });

  // ---- 护栏自身的牙齿：探测器不许**误报**（否则正经代码被它钉死），也不许漏报 ----
  group('探测器 flChartImporters / bareFlChartUsers', () {
    test('import 探测引号不敏感（双引号导入同样算违规）', () {
      expect(
        flChartImporters(const {
          'features/a.dart': "import 'package:fl_chart/fl_chart.dart';",
          'features/b.dart': 'import "package:fl_chart/fl_chart.dart";',
          'features/c.dart': '// 注释里提到 fl_chart，这不是导入',
        }),
        ['features/a.dart', 'features/b.dart'],
      );
    });

    test('适配器类名不算裸用（AppBarChart / AppGroupedBarChart / AppStackedBarChart）',
        () {
      // 回归：本探测原先用 `src.contains('BarChart(')`，被这三个类名里那截 `BarChart(`
      // 子串骗到——workbench_analysis / workbench_glance 明明只用适配器，却常年被这条
      // 护栏判红（ADR-0075 §2.3 护栏自带的 bug，与业务代码无关）。
      expect(
        bareFlChartUsers(const {
          'features/home/presentation/widgets/teacher/workbench_glance.dart':
              'child: AppGroupedBarChart(data: [])\nchild: AppStackedBarChart(data: [])',
          'features/home/presentation/widgets/teacher/workbench_analysis.dart':
              'child: AppBarChart(data: [])\nconst AppBarChart({super.key});',
        }),
        isEmpty,
      );
    });

    test('真·裸用 BarChart / PieChart 必被抓（否则护栏形同虚设）', () {
      expect(
        bareFlChartUsers(const {
          'features/a.dart': 'child: BarChart(BarChartData())',
          'features/b.dart': 'child: PieChart(PieChartData())',
          'features/c.dart': 'child: fl.BarChart(fl.BarChartData())',
        }),
        ['features/a.dart', 'features/b.dart', 'features/c.dart'],
      );
    });

    test('适配器自身豁免（它就是要 import / 用 fl_chart 的那一个）', () {
      expect(
        bareFlChartUsers(const {
          'shared/widgets/analytics_charts.dart':
              'child: BarChart(BarChartData())\nchild: PieChart(PieChartData())',
        }),
        isEmpty,
      );
    });
  });
}

/// fl_chart **图表构造器**的裸用探测（ADR-0075 §2.3 护栏）。
///
/// **必须词边界锚定**（`\b`）：适配器自己的类名 `AppBarChart(` / `AppGroupedBarChart(` /
/// `AppStackedBarChart(` 里都**含有**子串 `BarChart(`；裸 `contains('BarChart(')` 会把
/// 正经的适配器调用误判成违规。`\b` 保证只有当 `BarChart` / `PieChart` 自己是标识符
/// 的开头时才算「裸用 fl_chart 的构造器」。
final RegExp _bareFlChartCtor = RegExp(r'\b(?:Bar|Pie)Chart\(');

/// fl_chart 的 import 探测。**引号不敏感**：本仓未开 `prefer_single_quotes`，用双引号
/// 导入同样合法，只认单引号会漏掉一个「用双引号绕过护栏」的口子。
final RegExp _flChartImport = RegExp(r'''import\s+['"]package:fl_chart''');

/// 从「相对路径 → 源码」中挑出 import fl_chart 的文件。
List<String> flChartImporters(Map<String, String> sources) => [
      for (final e in sources.entries)
        if (_flChartImport.hasMatch(e.value)) e.key,
    ];

/// 从「相对路径 → 源码」中挑出裸用 fl_chart 图表构造器的文件（适配器自身除外）。
List<String> bareFlChartUsers(Map<String, String> sources) => [
      for (final e in sources.entries)
        if (e.key != 'shared/widgets/analytics_charts.dart' &&
            _bareFlChartCtor.hasMatch(e.value))
          e.key,
    ];
