// 旧 SceneSpec 向后兼容 + 快照不可变网守（ADR-0083 T03）。
//
// 存量 `Question.scene_spec` / `kp.scenes` 是**快照**（本轮纪律：零回写），形状是
// ADR-0083 之前的**老形**：几何塞在 `inputs[key=='points']`（或只留 `figure` 引用），
// 还带 `controls` / `narrative` / `title` / `outputs` / `editable`。本文件钉住适配层
// [adaptSceneSpec] 与读取入口 [ReflectionSceneData.fromSpec] 的五条契约：
// 1. 旧形 → 新形 `{kind, points, edges}`，几何不丢；
// 2. 旧数据无 `edges` → 按顶点顺序补默认闭合；
// 3. 旧 `controls` / `narrative` / `title` **不再被读取**（一律用 kind 外壳）；
// 4. `house` **仅极端兜底**（有顶点就绝不回退 house）；
// 5. 快照不可变：改库（图形预设）后，已落库快照的几何不变（几何全在 spec 里）。
//
// 挂载纪律（照 `scene_interpreter_curated_test.dart`）：根是 ShadApp + CupertinoApp，
// **不套 Material**（本仓无 Material 祖先，套了就测不出真实构建路径）。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/domain/figures.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene_data.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/scene_interpreter.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/scene_shells.dart';

/// 一个自定义三角形（**刻意不是内置预设**）：用来证明几何取自 spec 而非图形库。
const List<List<double>> _legacyTri = [
  [0.20, 0.80],
  [0.80, 0.80],
  [0.50, 0.30],
];

/// 一份**旧形**（ADR-0083 之前）的 reflection SceneSpec。
///
/// 几何在 `inputs[key=='points']`；另带 `controls` / `narrative` / `title` /
/// `outputs` / `editable`——都是新形已删除、但存量快照里仍存在的字段。
Map<String, dynamic> _legacySpec({
  List<List<double>> points = _legacyTri,
  String figure = '',
  double axisAngle = 90.0,
  bool editable = true,
}) =>
    <String, dynamic>{
      'kind': 'reflection',
      'title': '自定义·轴对称',
      'inputs': [
        {'key': 'axisAngle', 'label': '对称轴角度', 'value': axisAngle},
        {'key': 'axisX', 'value': 0.5},
        {'key': 'axisY', 'value': 0.5},
        {'key': 'figure', 'value': figure},
        {'key': 'points', 'value': points},
      ],
      'controls': {'play': true, 'pause': true, 'scrub': true, 'speed': true},
      'narrative': '这是旧文案，不应再被读取。',
      'outputs': {'isAxisymmetric': true},
      'editable': editable,
      'derivedFrom': 'figure_library',
    };

void main() {
  group('adaptSceneSpec 适配层', () {
    test('把旧 inputs[points] 上提为顶层几何', () {
      final adapted = adaptSceneSpec(_legacySpec());
      expect(adapted['kind'], 'reflection');
      expect(adapted['points'], _legacyTri);
    });

    test('旧数据无 edges → 按顶点顺序补默认闭合边', () {
      final adapted = adaptSceneSpec(_legacySpec());
      expect(adapted['edges'], closedEdges(3));
      expect(adapted['edges'], [
        [0, 1],
        [1, 2],
        [2, 0],
      ]);
    });

    test('丢弃旧 controls / narrative / title / outputs / inputs', () {
      final adapted = adaptSceneSpec(_legacySpec());
      for (final banned in const [
        'inputs',
        'controls',
        'narrative',
        'title',
        'outputs',
      ]) {
        expect(adapted.containsKey(banned), isFalse, reason: '$banned 应被丢弃');
      }
    });

    test('上提旧 axisAngle / axisX / axisY（存量轴初值仍被采信）', () {
      final adapted = adaptSceneSpec(_legacySpec(axisAngle: 0));
      expect(adapted['axisAngle'], 0);
      expect(adapted['axisX'], 0.5);
      expect(adapted['axisY'], 0.5);
    });

    test('上提旧 figure 引用（仅非空；空串占位丢弃）', () {
      expect(adaptSceneSpec(_legacySpec(figure: 'square'))['figure'], 'square');
      expect(adaptSceneSpec(_legacySpec(figure: ''))['figure'], isNull);
    });

    test('幂等：新形 {kind, points, edges} 原样通过', () {
      final fresh = <String, dynamic>{
        'kind': 'reflection',
        'points': _legacyTri,
        'edges': closedEdges(3),
      };
      final adapted = adaptSceneSpec(fresh);
      expect(adapted['kind'], 'reflection');
      expect(adapted['points'], _legacyTri);
      expect(adapted['edges'], closedEdges(3));
      expect(adapted.keys.toSet(), {'kind', 'points', 'edges'});
    });
  });

  group('fromSpec 读旧 spec', () {
    test('几何取自 inputs[points]（不丢）', () {
      final data = ReflectionSceneData.fromSpec(_legacySpec());
      expect(data.points.length, 3);
      expect(data.points.first, const Offset(0.20, 0.80));
      expect(data.points[2], const Offset(0.50, 0.30));
    });

    test('edges 按顶点顺序闭合', () {
      final data = ReflectionSceneData.fromSpec(_legacySpec());
      expect(data.edges, closedEdges(3));
    });

    test('narrative 取自 kind 外壳，不取旧文案', () {
      final data = ReflectionSceneData.fromSpec(_legacySpec());
      expect(data.narrative, shellFor('reflection').narrative);
      expect(data.narrative, isNot(contains('旧文案')));
    });

    test('采信旧 inputs 里的轴初值（存量观感不变）', () {
      final data = ReflectionSceneData.fromSpec(_legacySpec(axisAngle: 0));
      expect(data.axisAngle, 0.0);
    });

    test('兼容旧 editable 展示开关（可交互口径不变）', () {
      expect(
        ReflectionSceneData.fromSpec(_legacySpec(editable: false))
            .showAxisControls,
        isFalse,
      );
      expect(
        ReflectionSceneData.fromSpec(_legacySpec(editable: true))
            .showAxisControls,
        isTrue,
      );
      // 新形 spec 无 editable → 默认展示轴控件。
      final fresh = ReflectionSceneData.fromSpec(<String, dynamic>{
        'kind': 'reflection',
        'points': _legacyTri,
        'edges': closedEdges(3),
      });
      expect(fresh.showAxisControls, isTrue);
    });
  });

  group('几何回退链 / house 仅极端兜底', () {
    test('只有 figure key（无内联顶点）→ 回退 house（不再按 key 回查图库）', () {
      final data = ReflectionSceneData.fromSpec(
        _legacySpec(points: const [], figure: 'house'),
      );
      // ADR-0083 决策 7：运行时零图库依赖 → `figure` 引用键不再被解读，
      // 没有内联几何就统一兜到 kFallbackFigure。
      expect(data.points.length, kFallbackFigure.vertices.length);
      expect(
        data.points.first,
        Offset(kFallbackFigure.vertices.first.x, kFallbackFigure.vertices.first.y),
      );
    });

    test('figure key 对不上图库、又无顶点 → 同样回退 house（极端兜底）', () {
      final data = ReflectionSceneData.fromSpec(
        _legacySpec(points: const [], figure: '___gone___'),
      );
      expect(data.points.length, kFallbackFigure.vertices.length);
    });

    test('有内联顶点时绝不用 house（几何取自 spec）', () {
      // figure key 对不上、图库也不含该三角形——渲染仍用 spec 里的顶点。
      final data = ReflectionSceneData.fromSpec(_legacySpec(figure: '___gone___'));
      expect(data.points.length, 3);
      expect(data.points[2], const Offset(0.50, 0.30));
    });
  });

  group('快照不可变网守', () {
    test('已落库快照的几何完全来自 spec，不依赖图形库（改库不影响）', () {
      // snapshot 内联了 3 个顶点 + 一个「已从库中消失」的 figure key。若渲染去查库，
      // 会退化成 house（5 顶点）；正确行为是照 spec 顶点渲染（3 顶点）。
      final snapshot = _legacySpec(points: _legacyTri, figure: '___gone___');
      final data = ReflectionSceneData.fromSpec(snapshot);
      expect(data.points.length, 3, reason: '几何必须来自快照，不查库');
      expect(data.points.last, const Offset(0.50, 0.30));
    });
  });

  group('渲染（端到端经适配层）', () {
    testWidgets('旧形 spec 经适配后渲染正确、几何不丢', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            home: SingleChildScrollView(
              child: SceneInterpreter(kind: 'reflection', spec: _legacySpec()),
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
