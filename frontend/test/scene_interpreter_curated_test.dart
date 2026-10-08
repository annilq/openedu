// 场景解释器的三态分派（ADR-0076 §2.2 / §2.3 / §2.6）。
//
// 守四件事：
// 1. 无 optionGroup → 单场景，**是否可交互仍由 spec 的 editable 决定**（口径不变）；
// 2. curated: true → 只渲染条目解析出来的那几张，且**顺序 == 条目顺序**；
// 3. 有 optionGroup 但无 curated → 仍是整库网格 + 选项角标（题库路径一字不变）；
// 4. 弹窗的初始轴取**图形自带**的默认轴，不套用环节配置的轴。
//
// 为什么顺序断言必须用**逆库序**的条目：库序正序的子集在「被重排」与「未被重排」两种
// 实现下渲染结果相同，断言没有牙齿，守不住「教师编排的顺序不被悄悄重排」。
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

/// 课件语境的条目：**逆库序**（正方形 4 → 箭头 2 → 房子 0）。
///
/// 形状与后端 `extract_option_group` 一致（label / caption / figureKey / points /
/// defaultAxisAngle），课件语境没有 A/B/C，故 label 留空串。
List<Map<String, dynamic>> _curatedItems() => [
      _item(kFigureShapes[4]),
      _item(kFigureShapes[2]),
      _item(kFigureShapes[0]),
    ];

Map<String, dynamic> _item(FigureShape f, {String label = ''}) => {
      'label': label,
      'caption': f.label,
      'figureKey': f.key,
      // 保存时展开写入（ADR-0076 红线 2）：渲染层不回查图形库。
      'points': [
        for (final v in f.vertices) <double>[v.x, v.y],
      ],
      'defaultAxisAngle': f.defaultAxisAngle,
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

/// 题库语境的图形组：有条目、但**未声明** curated。
Map<String, dynamic> _plainGroup() => {
      'items': [
        _item(kFigureShapes[0], label: 'A'),
        _item(kFigureShapes[2], label: 'B'),
      ],
    };

Future<void> _pumpScene(
  WidgetTester tester,
  Map<String, dynamic> spec, {
  Size size = const Size(1200, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
      appBuilder: (context) => CupertinoApp(
        home: SingleChildScrollView(
          child: SceneInterpreter(kind: 'reflection', spec: spec),
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

  testWidgets('curated: true → 只渲染条目指定的图形，且顺序 == 条目顺序', (tester) async {
    await _pumpScene(tester, _sceneSpec(optionGroup: _curatedGroup()));

    expect(find.byType(ReflectionSceneWidget), findsNothing);
    expect(_cardLabels(tester), <String>[
      '播放正方形的对折演示',
      '播放箭头的对折演示',
      '播放房子的对折演示',
    ], reason: '逆库序的条目若被重排就说明顺序意图被抹掉了');
    expect(tester.takeException(), isNull);
  });

  testWidgets('curated: true → 不渲染选项角标（课件语境没有 A/B/C）', (tester) async {
    final group = {
      'curated': true,
      // 条目**故意**带 A/B/C：若实现照旧把它们传给画廊，这里就会出现角标。
      'items': [
        _item(kFigureShapes[4], label: 'A'),
        _item(kFigureShapes[2], label: 'B'),
        _item(kFigureShapes[0], label: 'C'),
      ],
    };
    await _pumpScene(tester, _sceneSpec(optionGroup: group));

    expect(_cardLabels(tester), hasLength(3));
    for (final badge in ['A', 'B', 'C']) {
      expect(find.text(badge), findsNothing, reason: '课件语境不该有选项角标');
    }
  });

  testWidgets('有 optionGroup 但未声明 curated → 仍是整库网格 + 选项角标',
      (tester) async {
    await _pumpScene(tester, _sceneSpec(optionGroup: _plainGroup()));

    final labels = _cardLabels(tester);
    expect(labels, hasLength(kFigureShapes.length), reason: '题库路径必须仍是整库');
    expect(labels.first, '播放房子的对折演示', reason: '带选项标号的仍排在最前');
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    // 与「curated 只渲染 3 张」正好相反：这条证明上一条的开关真的有牙齿。
    expect(find.text('平行四边形'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('curated 条目里出现库外图形 → 优雅跳过，不崩、不留空卡', (tester) async {
    final group = {
      'curated': true,
      'items': [
        _item(kFigureShapes[0]),
        {
          'label': '',
          'caption': '外星图形',
          'figureKey': 'alien',
          'points': [
            [0.11, 0.23],
            [0.91, 0.31],
            [0.47, 0.88],
          ],
          'defaultAxisAngle': 37.0,
        },
        _item(kFigureShapes[2]),
      ],
    };
    await _pumpScene(tester, _sceneSpec(optionGroup: group));

    expect(tester.takeException(), isNull);
    expect(_cardLabels(tester), <String>[
      '播放房子的对折演示',
      '播放箭头的对折演示',
    ], reason: '匹配不到的条目被跳过，且不留占位空卡');
    expect(find.text('外星图形'), findsNothing);
  });

  testWidgets('curated 点横向箭头 → 弹窗初始轴 0°，不套用环节的 90°', (tester) async {
    await _pumpScene(tester, _sceneSpec(optionGroup: _curatedGroup()));

    await tester.tap(find.text('箭头'));
    await tester.pumpAndSettle();

    expect(find.byType(ShadDialog), findsOneWidget);
    final data = _dialogScene(tester);
    expect(data.figureLabel, '箭头');
    expect(data.axisAngle, 0.0,
        reason: '唯一对称轴是横轴的图形，一打开就该是横轴（§2.6）');
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
