// 教师端「查看解析」的交互讲解（ADR-0061 §Q）。
//
// 回归背景：教师端「查看解析」原本只有一行 `解析：{文字}`，与学生端错题卡
// （早就渲染 scene_spec）行为分叉——教师看不到图形，就理解不了「为什么选 C」。
//
// 这里钉三件事：
// 1. 有 scene_spec 时展开区出图（图形在文字解析**之后**）；
// 2. 无 scene_spec 时行为与改动前完全一致（纯文字，不回归）；
// 3. **有图形但解析文字为空**时也要能展开（图形本身就是讲解）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/widgets/teacher/wrong_question_explanation.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';

/// 正方形 + 4 条对称轴（决策 A：轴对齐）。题干「正方形有几条对称轴」的形态。
Map<String, dynamic> _squareSpec() => {
      'kind': 'reflection',
      'inputs': [
        {'key': 'points', 'value': _squarePoints},
        {'key': 'axisAngle', 'value': 90.0},
        {'key': 'axisX', 'value': 0.5},
        {'key': 'axisY', 'value': 0.5},
      ],
      'controls': {'play': true, 'scrub': true},
      'narrative': '拖动对称轴，试出正方形的几条对称轴',
      'editable': true,
    };

const List<List<double>> _squarePoints = [
  [0.28, 0.28],
  [0.72, 0.28],
  [0.72, 0.72],
  [0.28, 0.72],
];

Widget _wrap(Widget child) => ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
      appBuilder: (context) => MaterialApp(
        home: Scaffold(body: child),
      ),
    );

/// 挂载并给定**真实表面尺寸**。
///
/// 必须 `setSurfaceSize`：默认测试表面只有 800×600，树上挂 `SizedBox` 改不了
/// 大小（父约束夹回 600）→ 场景画布（边长=宽度 的正方形）必然溢出。见
/// `docs/agents/frontend.md` §7。
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(500, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_wrap(child));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('有场景：展开后出图，且在文字解析之后', (tester) async {
    await _pump(tester, WrongQuestionExplanation(
      explanation: '正方形有 4 条对称轴，分别是两条对角线和两条中线。',
      sceneSpec: _squareSpec(),
      ),);

    // 初始折叠：只有按钮，无图无文
    expect(find.text('查看解析'), findsOneWidget);
    expect(find.byType(ReflectionSceneWidget), findsNothing);

    await tester.tap(find.text('查看解析'));
    await tester.pumpAndSettle();

    expect(find.textContaining('正方形有 4 条对称轴'), findsOneWidget);
    expect(find.byType(ReflectionSceneWidget), findsOneWidget);
    // 顺序：文字解析在图形之前（先结论、再动手验证）
    final textY = tester.getTopLeft(find.textContaining('正方形有 4 条对称轴')).dy;
    final sceneY = tester.getTopLeft(find.byType(ReflectionSceneWidget)).dy;
    expect(textY, lessThan(sceneY));
  });

  testWidgets('无场景：退化为纯文字（与改动前一致，零回归）', (tester) async {
    await _pump(tester, const WrongQuestionExplanation(explanation: '因为两边相等。'),);

    expect(find.text('查看解析'), findsOneWidget);
    await tester.tap(find.text('查看解析'));
    await tester.pumpAndSettle();

    expect(find.textContaining('因为两边相等'), findsOneWidget);
    expect(find.byType(ReflectionSceneWidget), findsNothing);
  });

  testWidgets('有图但解析文字为空：仍可展开（图形本身就是讲解）',
      (tester) async {
    await _pump(tester, WrongQuestionExplanation(explanation: '', sceneSpec: _squareSpec()),);

    // 关键：不能因为文字为空就整个不渲染——图形是唯一的内容
    expect(find.text('查看解析'), findsOneWidget);
    await tester.tap(find.text('查看解析'));
    await tester.pumpAndSettle();
    expect(find.byType(ReflectionSceneWidget), findsOneWidget);
  });

  testWidgets('既无场景又无文字：完全不渲染（不占位、不出空按钮）',
      (tester) async {
    await _pump(tester, const WrongQuestionExplanation(explanation: '   '),);

    expect(find.text('查看解析'), findsNothing);
    expect(find.byType(SizedBox), findsWidgets); // SizedBox.shrink 占位
    expect(tester.takeException(), isNull);
  });

  testWidgets('正方形渲染出的是 4 顶点（不是模板里的别的图形）', (tester) async {
    await _pump(tester, WrongQuestionExplanation(explanation: 'x', sceneSpec: _squareSpec()),);
    await tester.tap(find.text('查看解析'));
    await tester.pumpAndSettle();

    final data = tester
        .widget<ReflectionSceneWidget>(find.byType(ReflectionSceneWidget))
        .data;
    expect(data.points, hasLength(4), reason: '正方形必须是 4 个顶点');
  });

  testWidgets('editable=true → 学生/教师都能拖轴自己试', (tester) async {
    await _pump(tester, WrongQuestionExplanation(explanation: 'x', sceneSpec: _squareSpec()),);
    await tester.tap(find.text('查看解析'));
    await tester.pumpAndSettle();

    // 3 个轴控制（角度/水平/垂直）+ 1 个对折进度（未显式设 max → null）
    final sliders = tester.widgetList<ShadSlider>(find.byType(ShadSlider)).toList();
    expect(sliders.where((s) => s.max != null), hasLength(3));
  });
}
