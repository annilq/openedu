// 环节场景写入 optionGroup 的**拷贝语义**（ADR-0073 零回写 · ticket 05 核查项）。
//
// ticket 04 留下一个疑点：环节草稿里的场景 Map 可能是知识点场景快照的**同一个
// 实例**（`resolvedScene => scene` 只取顶层、`_associateScene` 用 `Map.from` 浅拷贝），
// 于是**嵌套**的 `optionGroup` 是共享的。若写入时就地改这个共享 Map，知识点上的场景
// 会被连带改写——这正是 ADR-0073 禁止的回写。
//
// 本文件故意让知识点模板**自带一个 optionGroup**，断言勾选 / 取消勾选前后它的快照
// 逐字段不变：
// 1. 勾到 ≥2 张：写出去的是**新 Map**，模板那份连嵌套的 optionGroup 都还是原对象；
// 2. 勾到 <2 张（闸门删键）：删的是副本上的键，模板的 optionGroup 一个不少。
//
// 为什么只挂选择器本身而不套整个编辑器页：被拷不拷贝发生在 [SectionSceneFiguresPicker]
// 的写入处，在这条更窄的接缝上断言能直接看见那份 Map，不必借道假仓库。
//
// 挂载纪律：整树**不套 Material**（根是 ShadApp + CupertinoApp）。
import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/courseware/presentation/pages/section_scene_figures_picker.dart';
import 'package:kids_learn/shared/domain/figures.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 知识点上的一份轴对称讲解模板——**自带**一个图形组（题库抽取出来的那种）。
///
/// 它就是断言对象：整份交给选择器当 `scene`，实现若就地改，这条用例立刻红。
Map<String, dynamic> _kpSpec() => <String, dynamic>{
      'kind': 'reflection',
      'title': '图形的运动（轴对称）',
      'editable': true,
      'optionGroup': <String, dynamic>{
        'items': <Map<String, dynamic>>[
          _item(kFigureShapes[0], label: 'A'),
          _item(kFigureShapes[2], label: 'B'),
        ],
      },
    };

Map<String, dynamic> _item(FigureShape f, {String label = ''}) => <String, dynamic>{
      'label': label,
      'caption': f.label,
      'figureKey': f.key,
      'points': <List<double>>[
        for (final v in f.vertices) <double>[v.x, v.y],
      ],
      'defaultAxisAngle': f.defaultAxisAngle,
    };

/// 挂上选择器，`onChanged` 的回执记进 [emitted]。
Future<void> _pumpPicker(
  WidgetTester tester,
  Map<String, dynamic> scene,
  void Function(Map<String, dynamic>) onChanged,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
      appBuilder: (context) => CupertinoApp(
        home: SingleChildScrollView(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SectionSceneFiguresPicker(scene: scene, onChanged: onChanged),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

List<String> _keysOf(Map<String, dynamic> group) =>
    (group['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((e) => e['figureKey'] as String)
        .toList();

void main() {
  testWidgets('勾到 ≥2 张：写出去的是副本，知识点模板（含嵌套 optionGroup）不变',
      (tester) async {
    final kpSpec = _kpSpec();
    final before = jsonEncode(kpSpec);
    final templateGroup = kpSpec['optionGroup'];
    Map<String, dynamic>? emitted;

    // 模板自带的 2 张（A / B）已播种 → 再勾正方形，凑够 3 张落库。
    await _pumpPicker(tester, kpSpec, (m) => emitted = m);
    await _toggle(tester, '正方形');

    expect(emitted, isNotNull);
    expect(jsonEncode(kpSpec), before,
        reason: '知识点上的场景被回写了（ADR-0073：只写本环节的副本）');
    expect(identical(kpSpec['optionGroup'], templateGroup), isTrue,
        reason: '模板的嵌套 optionGroup 被换掉了');
    // 写入确实发生了——否则「什么都没做」也会让上一条假通过。
    final group = emitted!['optionGroup'] as Map<String, dynamic>;
    expect(group['curated'], isTrue);
    expect(_keysOf(group), <String>['house', 'arrow', 'square']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('勾到 <2 张（闸门删键）：删的是副本上的键，模板的 optionGroup 还在',
      (tester) async {
    final kpSpec = _kpSpec();
    final before = jsonEncode(kpSpec);
    Map<String, dynamic>? emitted;

    await _pumpPicker(tester, kpSpec, (m) => emitted = m);
    // 模板播种了 2 张 → 取消一张即跌破闸门，走「删 optionGroup 键」这条分支。
    await _toggle(tester, '房子');

    expect(emitted, isNotNull);
    expect(emitted!.containsKey('optionGroup'), isFalse);
    expect(emitted!['kind'], 'reflection', reason: '只删 optionGroup，别把 scene 清空');
    expect(jsonEncode(kpSpec), before,
        reason: '删键落到了共享的那份模板上（就地 remove 会污染知识点场景）');
    expect(tester.takeException(), isNull);
  });
}
