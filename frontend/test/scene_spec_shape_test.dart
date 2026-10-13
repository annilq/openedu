// SceneSpec 形状契约（ADR-0083 T03 → ADR-0091）：旧形**不再被兼容**。
//
// ADR-0091 删掉了适配层（此前的 `adaptSceneSpec`）：统一后代码只认新形
// `{kind, figure?, options?, curated}`，旧形（顶层 `points`/`edges`、
// `optionGroup`、`inputs`）一律**拒绝**——双读分支正是「两套形状」的持久化，
// 留着就白统一了。本文件钉住读取入口 [ReflectionSceneData.fromSpec] 与解释器
// [SceneInterpreter] 的契约：
// 1. 新形直读：几何取自 `figure`（顶点 + 连接关系），不丢；
// 2. 缺 `edges` 时按顶点顺序闭合；
// 3. narrative / 轴初值取自 kind 外壳，不取 spec 里的旧文案 / 旧轴值；
// 4. house **仅极端兜底**（有 figure 就绝不回退 house）；
// 5. 旧形经解释器 → 空态（不臆造几何、不静默适配）；
// 6. 快照不可变：改库（图形预设）后，已落库快照的几何不变（几何全在 spec 里）。
//
// 挂载纪律（照 `scene_interpreter_curated_test.dart`）：根是 ShadApp + CupertinoApp，
// **不套 Material**（本仓无 Material 祖先，套了就测不出真实构建路径）。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/domain/figures.dart';
import 'package:kids_learn/shared/domain/scene_spec.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_empty_state.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene_data.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/scene_interpreter.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/scene_shells.dart';

/// 一个自定义三角形（**刻意不是内置预设**）：用来证明几何取自 spec 而非图形库。
const List<List<double>> _tri = [
  [0.20, 0.80],
  [0.80, 0.80],
  [0.50, 0.30],
];

/// 一份**新形** reflection SceneSpec：几何在 `figure` 里（带身份键）。
Map<String, dynamic> _freshSpec({
  List<List<double>> points = _tri,
  List<List<int>>? edges,
}) =>
    <String, dynamic>{
      'kind': 'reflection',
      'figure': <String, dynamic>{
        'key': 'user_tri',
        'label': '自定义三角形',
        'points': points,
        if (edges != null) 'edges': edges,
      },
    };

/// 一份**旧形**（ADR-0083 之前）spec：几何摊平在顶层，另带已废字段。
Map<String, dynamic> _legacySpec() => <String, dynamic>{
      'kind': 'reflection',
      'title': '自定义·轴对称',
      'points': _tri,
      'edges': closedEdges(3),
      'controls': {'play': true, 'pause': true, 'scrub': true, 'speed': true},
      'narrative': '这是旧文案，不应再被读取。',
      'outputs': {'isAxisymmetric': true},
      'editable': false,
      'derivedFrom': 'figure_library',
    };

/// 旧形选项组：`optionGroup.items[]`（ADR-0091 起这层嵌套没了）。
Map<String, dynamic> _legacyGroupSpec() => <String, dynamic>{
      'kind': 'reflection',
      'optionGroup': <String, dynamic>{
        'curated': true,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'label': 'A',
            'caption': '房子',
            'points': _tri,
          },
        ],
      },
    };

void main() {
  group('fromSpec 读新形 spec', () {
    test('几何取自 figure（不丢）', () {
      final data = ReflectionSceneData.fromSpec(
        SceneSpec.tryParse(_freshSpec())!,
      );
      expect(data.points.length, 3);
      expect(data.points.first, const Offset(0.20, 0.80));
      expect(data.points[2], const Offset(0.50, 0.30));
    });

    test('edges 随 figure 进来；缺 edges 时按顶点顺序闭合', () {
      final withEdges = ReflectionSceneData.fromSpec(
        SceneSpec.tryParse(_freshSpec(edges: const [
          [0, 1],
          [1, 2],
          [2, 0],
        ]))!,
      );
      expect(withEdges.edges, hasLength(3));

      final withoutEdges =
          ReflectionSceneData.fromSpec(SceneSpec.tryParse(_freshSpec())!);
      expect(withoutEdges.edges, closedEdges(3));
    });

    test('narrative / 轴初值取自 kind 外壳，不取 spec 里的旧值', () {
      // 新形 spec 只存几何；旧形里那些 axisAngle / narrative 已归外壳
      // （ADR-0083 决策 5 / ADR-0091：解析入口连旧字段都不看）。
      final data = ReflectionSceneData.fromSpec(
        SceneSpec.tryParse(_freshSpec())!,
      );
      expect(data.narrative, shellFor('reflection').narrative);
      expect(data.axisAngle, shellFor('reflection').axisAngle);
      expect(data.axisX, shellFor('reflection').axisX);
    });
  });

  group('house 仅极端兜底', () {
    test('figure 缺失（{kind}-only / 旧形被拒绝）→ 回退 house', () {
      final data = ReflectionSceneData.fromSpec(
        const SceneSpec(kind: 'reflection'),
      );
      // ADR-0083 决策 7：运行时零图库依赖；没有内联几何就统一兜到
      // kFallbackFigure（渲染期兜底，不参与落库）。
      expect(data.points.length, kFallbackFigure.vertices.length);
      expect(
        data.points.first,
        Offset(kFallbackFigure.vertices.first.x, kFallbackFigure.vertices.first.y),
      );
    });

    test('有 figure 时绝不用 house（几何取自 spec）', () {
      final data = ReflectionSceneData.fromSpec(
        SceneSpec.tryParse(_freshSpec())!,
      );
      expect(data.points.length, 3);
      expect(data.points[2], const Offset(0.50, 0.30));
    });
  });

  group('旧形被拒绝（不做双读）', () {
    test('旧形（顶层 points/edges）解析不出几何', () {
      final spec = SceneSpec.tryParse(_legacySpec())!;
      expect(spec.figure, isNull, reason: '旧形不被适配成新形（ADR-0091 决策 5）');
      expect(spec.options, isEmpty);
    });

    test('旧形选项组（optionGroup）解析不出选项', () {
      final spec = SceneSpec.tryParse(_legacyGroupSpec())!;
      expect(spec.options, isEmpty);
      expect(spec.curated, isFalse);
    });

    testWidgets('旧形 spec 经解释器 → 空态（不臆造几何、不画兜底房子）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            home: SingleChildScrollView(
              child: SceneInterpreter(
                spec: SceneSpec.tryParse(_legacySpec())!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ReflectionSceneWidget), findsNothing);
      expect(find.byType(AppEmptyState), findsOneWidget,
          reason: '旧形一律拒绝：走空态讲清「为什么空」，而不是静默画个兜底图形');
    });
  });

  group('快照不可变网守', () {
    test('已落库快照的几何完全来自 spec，不依赖图形库（改库不影响）', () {
      // snapshot 内联了 3 个顶点 + 一个「已从库中消失」的身份键。若渲染去查库，
      // 会退化成 house（5 顶点）；正确行为是照 spec 顶点渲染（3 顶点）。
      final data = ReflectionSceneData.fromSpec(
        SceneSpec.tryParse(_freshSpec())!,
      );
      expect(data.points.length, 3, reason: '几何必须来自快照，不查库');
      expect(data.points.last, const Offset(0.50, 0.30));
    });
  });

  group('渲染（端到端，新形直读）', () {
    testWidgets('新形 spec 渲染正确、几何不丢', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            home: SingleChildScrollView(
              child: SceneInterpreter(
                spec: SceneSpec.tryParse(_freshSpec())!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final widget = tester.widget<ReflectionSceneWidget>(
        find.byType(ReflectionSceneWidget),
      );
      expect(widget.data.points.length, 3);
      expect(widget.data.edges, closedEdges(3));
    });
  });
}
