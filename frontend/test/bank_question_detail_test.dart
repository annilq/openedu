// 题库题目详情弹窗（ADR-0061 §S）。
//
// 回归背景：题库列表是**扫描式**的（一眼看有没有要用的题），但「这题讲什么」需要
// **停留式**阅读 —— 列表里题干截断 2 行、没有选项/答案/解析、也完全没有图形。
//
// 这里钉四件事：
// 1. 详情含题干全文 + 选项 + 答案 + 解析；
// 2. 详情含**知识点信息**（学科/年级/学期/知识点/引用数）——学期是 ADR-0061 §J 的
//    第四维，'' 必须显示成「整学年」而不是空白；
// 3. 有 scene_spec → 渲染交互讲解；无 → **不占位**（没配模板是常态不是异常）；
// 4. 列表整卡 onTap 仍是「多选」，详情走**显式入口**（不劫持批量操作）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/presentation/widgets/parent/bank_question_detail.dart';
import 'package:kids_learn/shared/domain/models/question.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';

BankQuestionItem _item({
  String semester = '下学期',
  Map<String, dynamic>? sceneSpec,
  List<String>? options = const ['房子', '风筝', '箭头', '平行四边形'],
  int usageCount = 3,
  String explanation = '正方形有 4 条对称轴：两条中线 + 两条对角线。',
}) =>
    BankQuestionItem(
      id: 'q1',
      subject: '数学',
      grade: 4,
      stem: '正方形有几条对称轴？',
      options: options,
      qtype: 'choice',
      knowledgePoint: '图形的运动（轴对称）',
      difficulty: '中等',
      answer: 'C. 4条',
      explanation: explanation,
      usageCount: usageCount,
      semester: semester,
      sceneSpec: sceneSpec,
    );

Map<String, dynamic> _squareSpec() => {
      'kind': 'reflection',
      'inputs': [
        {
          'key': 'points',
          'value': [
            [0.28, 0.28],
            [0.72, 0.28],
            [0.72, 0.72],
            [0.28, 0.72],
          ],
        },
        {'key': 'axisAngle', 'value': 90.0},
        {'key': 'axisX', 'value': 0.5},
        {'key': 'axisY', 'value': 0.5},
      ],
      'controls': {'play': true, 'scrub': true},
      'editable': true,
    };

Future<void> _pump(WidgetTester tester, BankQuestionItem item) async {
  await tester.binding.setSurfaceSize(const Size(700, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp.custom(
    theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
    appBuilder: (context) => MaterialApp(home: Scaffold(body: BankQuestionDetail(item: item))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('详情含题干全文 / 选项 / 答案 / 解析', (tester) async {
    await _pump(tester, _item());
    expect(find.text('正方形有几条对称轴？'), findsOneWidget);
    // 选项标号按位置生成（A/B/C/D），与做题/纸质导出一致
    expect(find.text('A. 房子'), findsOneWidget);
    expect(find.text('D. 平行四边形'), findsOneWidget);
    expect(find.textContaining('标准答案：C. 4条'), findsOneWidget);
    expect(find.textContaining('正方形有 4 条对称轴'), findsOneWidget);
  });

  testWidgets('详情含知识点信息（学期不能是空白）', (tester) async {
    await _pump(tester, _item(semester: '下学期'));
    expect(find.text('知识点信息'), findsOneWidget);
    expect(find.text('图形的运动（轴对称）'), findsOneWidget);
    expect(find.text('下学期'), findsOneWidget);
    expect(find.text('4年级'), findsOneWidget);
    expect(find.text('被引用'), findsOneWidget);
  });

  testWidgets("semester='' 显示成「整学年」而不是空白", (tester) async {
    // '' = 整学年/不限（ADR-0061 §J）—— 直接渲染会是个空标签，看起来像 bug
    await _pump(tester, _item(semester: ''));
    expect(find.text('整学年'), findsOneWidget);
  });

  testWidgets('有 scene_spec → 渲染交互讲解', (tester) async {
    await _pump(tester, _item(sceneSpec: _squareSpec()));
    expect(find.text('交互讲解'), findsOneWidget);
    expect(find.byType(ReflectionSceneWidget), findsOneWidget);
  });

  testWidgets('无 scene_spec → 不占位（没配模板是常态，不是异常）', (tester) async {
    await _pump(tester, _item());
    expect(find.byType(ReflectionSceneWidget), findsNothing);
    expect(find.text('交互讲解'), findsNothing);
    // 详情本身仍完整可用
    expect(find.text('正方形有几条对称轴？'), findsOneWidget);
  });

  testWidgets('场景画布被压窄（正方形边长=宽度，不压会顶破弹窗）', (tester) async {
    await _pump(tester, _item(sceneSpec: _squareSpec()));
    final w = tester.getSize(find.byType(ReflectionSceneWidget)).width;
    expect(w, lessThanOrEqualTo(BankQuestionDetail.sceneMaxWidthForTest));
  });

  testWidgets('关闭按钮可关掉弹窗', (tester) async {
    var popped = false;
    await tester.binding.setSurfaceSize(const Size(700, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
      appBuilder: (context) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => BankQuestionDetail.show(ctx, _item()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ReflectionSceneWidget), findsNothing); // 本例无场景
    await tester.tap(find.bySemanticsLabel('关闭'));
    await tester.pumpAndSettle();
    popped = true;
    expect(popped, isTrue);
    expect(find.text('open'), findsOneWidget); // 弹窗已关
  });
}
