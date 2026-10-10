// 场景解释器的三态分派（ADR-0076 §2.2 / §2.3 / §2.6）。
//
// 守四件事：
// 1. 无 optionGroup → 单场景，**是否可交互由 spec 的旧形 editable 或调用方显式开关
//    决定**（存量口径不变；新代码走 [SceneInterpreter.showAxisControls]，不再塞 editable）；
// 2. 有 optionGroup → **只摆条目里那几个图形**，且顺序 == 条目顺序（库里几个、怎么排
//    都是后端下发的，渲染不再查图库——ADR-0083 决策 7 的零图库依赖）；
// 3. 条目自带几何 → 图库里没有的图形照样能渲染（渲染路径不认识图库）；
// 4. 弹窗的初始轴取 **kind 外壳**的初值（reflection = 90°），不按图形走
//    （ADR-0083 决策 6：轴初值归 kind 外壳，图形不带 axis 属性）。
//
// 为什么顺序断言必须用**非库序**的条目：按同一顺序排的子集在「被重排」与「未被重排」
// 两种实现下渲染结果相同，断言没有牙齿，守不住「教师编排的顺序不被悄悄重排」。
//
// 挂载纪律：根是 ShadApp + CupertinoApp，**不套 Material**（本仓无 Material 祖先，
// 套了就测不出真实构建路径）；多列布局必须 setSurfaceSize。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/domain/figures.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/widgets/app_slider.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_figure_gallery.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene_data.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/scene_interpreter.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/scene_shells.dart';

import 'support/figure_fixtures.dart';

/// 课件语境的条目：**非库序**（正方形 → 箭头 → 房子）。
///
/// 形状与后端 `extract_option_group` 一致（label / caption / points / edges），
/// 课件语境没有 A/B/C，故 label 留空串。
List<Map<String, dynamic>> _curatedItems() => [
      _item(kSquareFixture),
      _item(kArrowFixture),
      _item(kHouseFixture),
    ];

Map<String, dynamic> _item(FigureShape f, {String label = ''}) => {
      'label': label,
      'caption': f.label,
      // 保存时展开写入（ADR-0076 红线 2）：渲染层不回查图形库。
      'points': [
        for (final v in f.vertices) <double>[v.x, v.y],
      ],
      'edges': closedEdges(f.vertices.length),
    };

/// 一份环节场景数据：模板轴是 90°（竖轴），用来验证弹窗**不套用**它。
Map<String, dynamic> _sceneSpec({
  Map<String, dynamic>? optionGroup,
  bool editable = true,
}) =>
    {
      'kind': 'reflection',
      'inputs': [
        {'key': 'figure', 'value': 'house'},
        {'key': 'axisAngle', 'value': 90.0},
        {'key': 'axisX', 'value': 0.5},
        {'key': 'axisY', 'value': 0.5},
      ],
      'controls': {'play': true, 'scrub': true},
      'narrative': '拖动对称轴试试看能否完全重合',
      'editable': editable,
      if (optionGroup != null) 'optionGroup': optionGroup,
    };

Map<String, dynamic> _curatedGroup() => {
      'curated': true,
      'items': _curatedItems(),
    };

/// 题库语境的图形组：有条目、但**未声明** curated（区别只在「挂不挂 A/B/C 角标」）。
Map<String, dynamic> _plainGroup() => {
      'items': [
        _item(kHouseFixture, label: 'A'),
        _item(kArrowFixture, label: 'B'),
      ],
    };

Future<void> _pumpScene(
  WidgetTester tester,
  Map<String, dynamic> spec, {
  Size size = const Size(1200, 900),
  bool? showAxisControls,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
      appBuilder: (context) => CupertinoApp(
        home: SingleChildScrollView(
          child: SceneInterpreter(
            kind: 'reflection',
            spec: spec,
            showAxisControls: showAxisControls,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 卡片顺序（树序 == 布局序），取每张卡的读屏标签即图形名。
List<String?> _cardLabels(WidgetTester tester) => tester
    .widgetList<AppFocusableAction>(find.byType(AppFocusableAction))
    .map((w) => w.semanticLabel)
    .toList();

/// 弹窗里那个场景的数据（初始轴 / 顶点 / 图形名都在上面）。
ReflectionSceneData _dialogScene(WidgetTester tester) => tester
    .widget<ReflectionSceneWidget>(
      find.descendant(
        of: find.byType(ShadDialog),
        matching: find.byType(ReflectionSceneWidget),
      ),
    )
    .data;

void main() {
  testWidgets('无 optionGroup → 单场景，不渲染画廊', (tester) async {
    await _pumpScene(tester, _sceneSpec(), size: const Size(420, 1000));

    expect(find.byType(SceneOptionGroup), findsNothing);
    expect(find.byType(ReflectionFigureGallery), findsNothing);
    expect(find.byType(ReflectionSceneWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无 optionGroup 时是否可交互仍由 editable 决定（口径不变）',
      (tester) async {
    // editable=false：只有 1 个对折进度条，3 个轴控制整个不出现。
    await _pumpScene(
      tester,
      _sceneSpec(editable: false),
      size: const Size(420, 1000),
    );
    expect(find.byType(AppSlider), findsOneWidget);

    await _pumpScene(tester, _sceneSpec(), size: const Size(420, 1000));
    expect(find.byType(AppSlider), findsNWidgets(4),
        reason: 'editable=true → 3 个轴控制 + 1 个对折进度条');
  });

  testWidgets('showAxisControls 显式开关覆盖 spec（新代码不再塞旧形 editable）',
      (tester) async {
    // 传 false 摘掉轴滑块：只留 1 个对折进度条——场景库详情页的静态缩略图正是这条路，
    // 它因此不必再往 spec 里写 `editable: false`/`controls`/`narrative`（ADR-0083 决策 5）。
    await _pumpScene(
      tester,
      _sceneSpec(),
      size: const Size(420, 1000),
      showAxisControls: false,
    );
    expect(find.byType(AppSlider), findsOneWidget);

    // 反向也要成立：spec 里旧形 `editable: false` 被显式 true 盖掉——证明是开关说了算，
    // 而不是「spec 恰好没写」。
    await _pumpScene(
      tester,
      _sceneSpec(editable: false),
      size: const Size(420, 1000),
      showAxisControls: true,
    );
    expect(find.byType(AppSlider), findsNWidgets(4));

    // 不给开关（null）时口径完全不变：仍按 spec 推断。
    await _pumpScene(
      tester,
      _sceneSpec(editable: false),
      size: const Size(420, 1000),
    );
    expect(find.byType(AppSlider), findsOneWidget);
  });

  testWidgets('curated: true → 只渲染条目指定的图形，且顺序 == 条目顺序', (tester) async {
    await _pumpScene(tester, _sceneSpec(optionGroup: _curatedGroup()));

    expect(find.byType(ReflectionSceneWidget), findsNothing);
    expect(_cardLabels(tester), <String>[
      '播放正方形的对折演示',
      '播放箭头的对折演示',
      '播放房子的对折演示',
    ], reason: '非库序的条目若被重排就说明顺序意图被抹掉了');
    expect(tester.takeException(), isNull);
  });

  testWidgets('curated: true → 不渲染选项角标（课件语境没有 A/B/C）', (tester) async {
    final group = {
      'curated': true,
      // 条目**故意**带 A/B/C：若实现照旧把它们传给画廊，这里就会出现角标。
      'items': [
        _item(kSquareFixture, label: 'A'),
        _item(kArrowFixture, label: 'B'),
        _item(kHouseFixture, label: 'C'),
      ],
    };
    await _pumpScene(tester, _sceneSpec(optionGroup: group));

    expect(_cardLabels(tester), hasLength(3));
    for (final badge in ['A', 'B', 'C']) {
      expect(find.text(badge), findsNothing, reason: '课件语境不该有选项角标');
    }
  });

  testWidgets('有 optionGroup 但未声明 curated → 同样的条目 + 挂上选项角标',
      (tester) async {
    await _pumpScene(tester, _sceneSpec(optionGroup: _plainGroup()));

    final labels = _cardLabels(tester);
    // 渲染路径零图库依赖（ADR-0083 决策 7）：摆的就是条目里这两个，不再铺「整库」。
    expect(labels, <String>['播放房子的对折演示', '播放箭头的对折演示'],
        reason: '条目顺序 == 卡片顺序');
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    // 与「curated 不挂角标」正好相反：这条证明那个开关真的有牙齿。
    expect(tester.takeException(), isNull);
  });

  testWidgets('条目自带几何 → 图库里没有的图形照样渲染（渲染不查库）', (tester) async {
    final group = {
      'curated': true,
      'items': [
        _item(kHouseFixture),
        {
          'label': '',
          'caption': '外星图形',
          'points': [
            [0.11, 0.23],
            [0.91, 0.31],
            [0.47, 0.88],
          ],
          'edges': [
            [0, 1],
            [1, 2],
            [2, 0],
          ],
        },
        _item(kArrowFixture),
      ],
    };
    await _pumpScene(tester, _sceneSpec(optionGroup: group));

    expect(tester.takeException(), isNull);
    expect(_cardLabels(tester), <String>[
      '播放房子的对折演示',
      '播放外星图形的对折演示',
      '播放箭头的对折演示',
    ], reason: '几何内联在条目里 → 库外图形也该摆得出来，不是被跳过');
  });

  testWidgets('curated 点横向箭头 → 弹窗初始轴仍取 kind 外壳的 90°', (tester) async {
    await _pumpScene(tester, _sceneSpec(optionGroup: _curatedGroup()));

    await tester.tap(find.text('箭头'));
    await tester.pumpAndSettle();

    expect(find.byType(ShadDialog), findsOneWidget);
    final data = _dialogScene(tester);
    expect(data.figureLabel, '箭头');
    expect(data.axisAngle, shellFor('reflection').axisAngle,
        reason: '轴初值归 kind 外壳（ADR-0083 决策 6）：图形自己不带 axis 属性');
  });

  testWidgets('curated 点正方形 → 弹窗内可旋转 / 平移对称轴，初始轴 90°', (tester) async {
    await _pumpScene(tester, _sceneSpec(optionGroup: _curatedGroup()));

    await tester.tap(find.text('正方形'));
    await tester.pumpAndSettle();

    final data = _dialogScene(tester);
    expect(data.figureLabel, '正方形');
    expect(data.axisAngle, 90.0);
    // 3 个轴控制（角度 / 水平 / 垂直）+ 1 个对折进度条 = 旋转与平移都在。
    expect(
      tester.widgetList<AppSlider>(find.byType(AppSlider)),
      hasLength(4),
      reason: '弹窗里必须还能旋转与平移对称轴',
    );
  });

  testWidgets('curated 只读卡上没有任何「是否轴对称」的判定标记', (tester) async {
    await _pumpScene(tester, _sceneSpec(optionGroup: _curatedGroup()));

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(texts.any((t) => t.contains('轴对称') || t.contains('不对称')), isFalse,
        reason: '只读视图标了答案，「点开亲手折」当场死亡（§2.5）');
    expect(find.byIcon(LucideIcons.check), findsNothing);
    expect(find.byIcon(LucideIcons.x), findsNothing);
  });
}
