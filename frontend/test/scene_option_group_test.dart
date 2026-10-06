// 选项组渲染（ADR-0061 §V）：同一模板 → 图形画廊，点一个图形弹对折演示。
//
// 守三件事：
// 1. spec 带 optionGroup 时**不再**平铺 N 个场景（§O 旧做法），而是渲染图形画廊；
// 2. 点一个图形弹 ReflectionSceneDialog，框里是**该图形自己的**完整场景
//    （拖 A 的轴不影响 B，每次只演示一个）；
// 3. 每个场景用**该图形自己的**默认轴，不用模板的（否则箭头停在竖轴、一开始就不重合）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/widgets/app_slider.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_figure_gallery.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene_data.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/scene_interpreter.dart';

Map<String, dynamic> _specWithGroup() => {
      'kind': 'reflection',
      // 模板默认：房子 + 竖轴（教师配的默认值）
      'inputs': [
        {'key': 'figure', 'value': 'house'},
        {'key': 'axisAngle', 'value': 90.0},
        {'key': 'axisX', 'value': 0.5},
        {'key': 'axisY', 'value': 0.5},
      ],
      'controls': {'play': true, 'scrub': true},
      'narrative': '拖动对称轴试试看能否完全重合',
      'editable': true,
      'optionGroup': {
        'items': [
          {
            'label': 'A',
            'caption': '房子',
            'figureKey': 'house',
            'points': [
              [0.30, 0.70],
              [0.70, 0.70],
              [0.70, 0.45],
              [0.50, 0.25],
              [0.30, 0.45],
            ],
            'defaultAxisAngle': 90.0,
          },
          {
            'label': 'B',
            'caption': '箭头',
            'figureKey': 'arrow',
            'points': [
              [0.20, 0.42],
              [0.62, 0.42],
              [0.62, 0.30],
              [0.82, 0.50],
              [0.62, 0.70],
              [0.62, 0.58],
              [0.20, 0.58],
            ],
            // 横向图形 → 0°（关键：不能沿用模板的 90°）
            'defaultAxisAngle': 0.0,
          },
        ],
      },
    };

/// 按给定**表面尺寸**挂载场景。
///
/// 必须走 `tester.binding.setSurfaceSize`：默认测试表面只有 800×600，光在树上挂个
/// `SizedBox` 改不了大小——父约束会把它夹回 600，`MediaQuery` 也仍是 800，导致
/// 「两列并排」根本触发不了、还会误报 RenderFlex 溢出。
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
      appBuilder: (context) => MaterialApp(
        home: Scaffold(body: SceneInterpreter(kind: 'reflection', spec: spec)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 画廊里点开某个图形（按中文名定位卡片）。
Finder _galleryCard(String figureLabel) =>
    find.ancestor(of: find.text(figureLabel), matching: find.byType(AppFocusableAction));

void main() {
  testWidgets('optionGroup → 渲染图形画廊（不平铺 N 个场景）', (tester) async {
    await _pumpScene(tester, _specWithGroup());

    // §V：列表页铺画廊，每个图形一个卡片；场景只在弹窗里，不在这里平铺。
    expect(find.byType(SceneOptionGroup), findsOneWidget);
    expect(find.byType(ReflectionFigureGallery), findsOneWidget);
    expect(find.byType(ReflectionSceneWidget), findsNothing);
  });

  testWidgets('点选项 A（房子）打开弹窗，场景用房子默认轴 90°', (tester) async {
    await _pumpScene(tester, _specWithGroup());

    await tester.tap(_galleryCard('房子'));
    await tester.pumpAndSettle();

    expect(find.byType(ShadDialog), findsOneWidget);
    final data = tester
        .widget<ReflectionSceneWidget>(
          find.descendant(
            of: find.byType(ShadDialog),
            matching: find.byType(ReflectionSceneWidget),
          ),
        )
        .data;
    // 房子默认竖轴 90°
    expect(data.figureLabel, '房子');
    expect(data.axisAngle, 90.0);
  });

  testWidgets('点选项 B（箭头）打开弹窗，场景用箭头默认轴 0°（不被模板 90° 覆盖）',
      (tester) async {
    await _pumpScene(tester, _specWithGroup());

    await tester.tap(_galleryCard('箭头'));
    await tester.pumpAndSettle();

    final data = tester
        .widget<ReflectionSceneWidget>(
          find.descendant(
            of: find.byType(ShadDialog),
            matching: find.byType(ReflectionSceneWidget),
          ),
        )
        .data;
    // 横向箭头必须回到它自己的 0°，而不是模板的 90°
    expect(data.figureLabel, '箭头');
    expect(data.axisAngle, 0.0);
  });

  testWidgets('点选项 A 打开的弹窗里，顶点是该图形自己的（房子 5 点）', (tester) async {
    await _pumpScene(tester, _specWithGroup());

    await tester.tap(_galleryCard('房子'));
    await tester.pumpAndSettle();

    final data = tester
        .widget<ReflectionSceneWidget>(
          find.descendant(
            of: find.byType(ShadDialog),
            matching: find.byType(ReflectionSceneWidget),
          ),
        )
        .data;
    expect(data.points.length, 5);
  });

  testWidgets('选项标号与图形名都显示在画廊里（让学生知道在试哪个）', (tester) async {
    await _pumpScene(tester, _specWithGroup());

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('房子'), findsOneWidget);
    expect(find.text('箭头'), findsOneWidget);
  });

  testWidgets('无 optionGroup 时仍渲染单场景（旧数据零回归）', (tester) async {
    final spec = _specWithGroup()..remove('optionGroup');
    // 用**贴近真实的卡片宽度**：单场景的画布是「边长 = 宽度」的正方形
    // （ReflectionSceneWidget 的既有行为，本次未改），全屏宽会让它高得离谱。
    await _pumpScene(tester, spec, size: const Size(420, 1000));

    expect(find.byType(SceneOptionGroup), findsNothing);
    expect(find.byType(ReflectionSceneWidget), findsOneWidget);
  });

  testWidgets('optionGroup 存在但无有效 points → 走空态而非崩溃', (tester) async {
    final spec = _specWithGroup();
    (spec['optionGroup'] as Map)['items'] = [
      {'label': 'A', 'caption': '房子'}, // 没有 points
    ];
    await _pumpScene(tester, spec);

    // 不崩；无有效项 → 空态
    expect(tester.takeException(), isNull);
    expect(find.byType(ReflectionSceneWidget), findsNothing);
  });

  testWidgets('点播放能跑完对折动画（回归：控制器漏设 duration 直接抛）',
      (tester) async {
    // AnimationController 没给 duration 时，`forward()` 会在点击瞬间抛
    // "called with no default duration"——而这个崩溃只在**真的点了播放**时才
    // 暴露，构造/渲染阶段测不出来，所以必须走一次手势。
    await _pumpScene(tester, _specWithGroup(), size: const Size(500, 1200));

    await tester.tap(_galleryCard('房子'));
    await tester.pumpAndSettle();

    final playBtn = find.bySemanticsLabel('播放对折').first;
    expect(playBtn, findsOneWidget);
    await tester.tap(playBtn);
    await tester.pump(); // 启动动画
    expect(tester.takeException(), isNull, reason: '点播放不应抛异常');

    // 跑完整个对折动画（0 → 1），中途应出现「暂停」按钮
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.bySemanticsLabel('暂停对折'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));

    // 动画结束后回到「播放」态，且无异常
    expect(find.bySemanticsLabel('播放对折'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editable=true 时弹窗内显示 3 个轴控制 + 1 个对折进度（共 4 AppSlider）',
      (tester) async {
    await _pumpScene(tester, _specWithGroup());

    await tester.tap(_galleryCard('房子'));
    await tester.pumpAndSettle();

    // 弹窗内：3 个轴滑块（角度 0..180、水平 0.3..0.7、垂直 0.3..0.7）+ 1 个对折
    // 进度条（未显式设 max → null）。轴参数那 3 个正是 ①A 要的——editable=false
    // 时它们会整个消失，学生就只能看不能试。
    final all = tester.widgetList<AppSlider>(find.byType(AppSlider)).toList();
    expect(all, hasLength(4), reason: '弹窗内：3 个轴控制 + 1 个对折进度条');
    final axisSliders = all.where((s) => s.max != null).toList();
    final foldSliders = all.where((s) => s.max == null).toList();
    expect(axisSliders, hasLength(3), reason: '3 个轴控制 slider');
    expect(foldSliders, hasLength(1), reason: '1 个对折进度条（未显式设 max）');
  });
}
