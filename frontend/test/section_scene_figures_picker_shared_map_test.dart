// 环节场景写入 options 的**拷贝语义**（ADR-0073 零回写 · ticket 05 核查项 · ADR-0091 改形）。
//
// ticket 04 留下一个疑点：环节草稿里的场景 Map 可能是知识点场景快照的**同一个
// 实例**（`resolvedScene => scene` 只取顶层、`_associateScene` 用 `Map.from` 浅拷贝），
// 于是**嵌套**的 `options` 是共享的。若写入时就地改这个共享 List / Map，知识点上的场景
// 会被连带改写——这正是 ADR-0073 禁止的回写。
//
// 本文件故意让知识点模板**自带一组 options**，断言勾选 / 取消勾选前后它的快照
// 逐字段不变：
// 1. 勾到 ≥2 张：写出去的是**新 List**，模板那份连嵌套的 options 都还是原对象；
// 2. 勾到 <2 张（闸门删键）：删的是副本上的键，模板的 options 一个不少。
//
// 为什么只挂选择器本身而不套整个编辑器页：被拷不拷贝发生在 [SectionSceneFiguresPicker]
// 的写入处，在这条更窄的接缝上断言能直接看见那份 Map，不必借道假仓库。
//
// 挂载纪律：整树**不套 Material**（根是 ShadApp + CupertinoApp）。
import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/courseware/presentation/pages/section_scene_figures_picker.dart';
import 'package:kids_learn/shared/domain/figures.dart';
import 'package:kids_learn/shared/domain/providers/figure_library_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

import 'support/figure_fixtures.dart';

/// 知识点上的一份轴对称讲解模板——**自带**一组选项图形（题库抽取出来的那种）。
///
/// 它就是断言对象：整份交给选择器当 `scene`，实现若就地改，这条用例立刻红。
Map<String, dynamic> _kpSpec() => <String, dynamic>{
      'kind': 'reflection',
      'title': '图形的运动（轴对称）',
      'options': <Map<String, dynamic>>[
        _figure(kHouseFixture),
        _figure(kArrowFixture),
      ],
    };

/// 一个新形 `Figure`（与后端 `Figure` 同形：key / label / points / edges）。
Map<String, dynamic> _figure(FigureShape f) => <String, dynamic>{
      'key': f.key,
      'label': f.label,
      'points': <List<double>>[
        for (final v in f.vertices) <double>[v.x, v.y],
      ],
      'edges': <List<int>>[
        for (var i = 0; i < f.vertices.length; i++)
          <int>[i, (i + 1) % f.vertices.length],
      ],
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
    ProviderScope(
      // 挑图形的清单来自图库、打开时按需拉取（ADR-0083 决策 7）。
      overrides: [
        figureLibraryProvider.overrideWith((ref) async => kTestLibrary),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: SingleChildScrollView(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child:
                    SectionSceneFiguresPicker(scene: scene, onChanged: onChanged),
              ),
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

/// 条目里的图形名序列（`Figure.label`；身份键是 `key`，ADR-0091）。
List<String> _labelsOf(Map<String, dynamic> scene) =>
    (scene['options'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((e) => e['label'] as String)
        .toList();

void main() {
  testWidgets('勾到 ≥2 张：写出去的是副本，知识点模板（含嵌套 options）不变',
      (tester) async {
    final kpSpec = _kpSpec();
    final before = jsonEncode(kpSpec);
    final templateOptions = kpSpec['options'];
    Map<String, dynamic>? emitted;

    // 模板自带的 2 张（房子 / 箭头）已播种 → 再勾正方形，凑够 3 张落库。
    await _pumpPicker(tester, kpSpec, (m) => emitted = m);
    await _toggle(tester, '正方形');

    expect(emitted, isNotNull);
    expect(jsonEncode(kpSpec), before,
        reason: '知识点上的场景被回写了（ADR-0073：只写本环节的副本）');
    expect(identical(kpSpec['options'], templateOptions), isTrue,
        reason: '模板的嵌套 options 被换掉了');
    // 写入确实发生了——否则「什么都没做」也会让上一条假通过。
    expect(emitted!['curated'], isTrue);
    expect(_labelsOf(emitted!), <String>['房子', '箭头', '正方形']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('勾到 <2 张（闸门删键）：删的是副本上的键，模板的 options 还在',
      (tester) async {
    final kpSpec = _kpSpec();
    final before = jsonEncode(kpSpec);
    Map<String, dynamic>? emitted;

    await _pumpPicker(tester, kpSpec, (m) => emitted = m);
    // 模板播种了 2 张 → 取消一张即跌破闸门，走「删 options 键」这条分支。
    await _toggle(tester, '房子');

    expect(emitted, isNotNull);
    expect(emitted!.containsKey('options'), isFalse);
    expect(emitted!.containsKey('curated'), isFalse);
    expect(emitted!['kind'], 'reflection', reason: '只删 options，别把 scene 清空');
    expect(jsonEncode(kpSpec), before,
        reason: '删键落到了共享的那份模板上（就地 remove 会污染知识点场景）');
    expect(tester.takeException(), isNull);
  });
}
