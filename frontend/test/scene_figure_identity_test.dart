// 图形画廊的**身份缺陷回归**（ADR-0091 ticket 04）。
//
// 修复的缺陷：选项条目此前不带图库身份键，画廊只能拿**展示名**当身份键
// （`scene_interpreter.dart:220` 的 `key: name`）。于是——
//   ① 教师把「房子」改名成「小屋」，角标映射与高亮当场断；
//   ② 两个同名图形被 `seen` 静默合并成一张卡。
// 现在身份由 `figure.key` 承担，展示名回归它本来的用途：显示。
//
// 守四件事（都用**几何断言**，本仓禁止截图装置）：
// 1. 改展示名后，角标仍落在**同一张卡**上（角标矩形中心在卡片矩形内）；
// 2. 同名不同身份键 → 两张卡都在，不再被合并；
// 3. 同身份键重复 → 只一张卡（去重按身份键，不按名字）；
// 4. 渲染**不消费**身份键：内联顶点说了算，不按 key 回查图库。
//
// 挂载纪律：根是 ShadApp + CupertinoApp，**不套 Material**；多列布局必须
// `setSurfaceSize`，否则父约束把尺寸夹回 800×600、误报溢出。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/domain/scene_spec.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/widgets/app_slider.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/scene_interpreter.dart';

const List<List<double>> _tri = <List<double>>[
  <double>[0.20, 0.80],
  <double>[0.80, 0.80],
  <double>[0.50, 0.30],
];

const List<List<double>> _arrow = <List<double>>[
  <double>[0.20, 0.42],
  <double>[0.62, 0.42],
  <double>[0.62, 0.30],
  <double>[0.82, 0.50],
  <double>[0.62, 0.70],
  <double>[0.62, 0.58],
  <double>[0.20, 0.58],
];

/// 一个新形 `Figure`（与后端 `Figure` 同形：key / label / points / edges）。
Map<String, dynamic> _figure(
  String key,
  String label,
  List<List<double>> points,
) =>
    <String, dynamic>{
      'key': key,
      'label': label,
      'points': points,
      'edges': <List<int>>[
        for (var i = 0; i < points.length - 1; i++) [i, i + 1],
        [points.length - 1, 0],
      ],
    };

/// 题库语境（curated=false，选项挂 A/B/C 角标）的一份 spec。
Map<String, dynamic> _spec(List<Map<String, dynamic>> options) =>
    <String, dynamic>{
      'kind': 'reflection',
      'figure': _figure('tmpl', '模板图形', _tri),
      'options': options,
      'curated': false,
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
          child: SceneInterpreter(spec: SceneSpec.tryParse(spec)!),
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

/// 某张卡（按展示名定位）的矩形。
Rect _cardRect(WidgetTester tester, String label) => tester.getRect(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(AppFocusableAction),
      ),
    );

/// 角标 **落在** 这张卡上（角标矩形中心在卡片矩形内）。
///
/// 为什么用矩形而不是数角标个数：个数对得上、挂错了卡也算对——错位正是本次修的
/// 缺陷，断言必须能区分「挂对了」与「挂在了别的卡上」。
void _expectBadgeOnCard(WidgetTester tester, String badge, String label) {
  final badgeRect = tester.getRect(find.text(badge));
  expect(_cardRect(tester, label).contains(badgeRect.center), isTrue,
      reason: '角标「$badge」应挂在「$label」这张卡上（改展示名不得让映射错位）');
}

void main() {
  testWidgets('改图形的展示名后，角标仍挂在同一张卡上', (tester) async {
    await _pumpScene(
      tester,
      _spec([
        _figure('opt_a', '房子', _tri),
        _figure('opt_b', '箭头', _arrow),
      ]),
    );
    expect(_cardLabels(tester), <String>[
      '播放房子的对折演示',
      '播放箭头的对折演示',
    ]);
    _expectBadgeOnCard(tester, 'A', '房子');
    _expectBadgeOnCard(tester, 'B', '箭头');

    // 教师把「房子」改名成「小屋」：身份键没变，角标映射必须一字不变。
    await _pumpScene(
      tester,
      _spec([
        _figure('opt_a', '小屋', _tri),
        _figure('opt_b', '箭头', _arrow),
      ]),
    );
    expect(_cardLabels(tester), <String>[
      '播放小屋的对折演示',
      '播放箭头的对折演示',
    ]);
    _expectBadgeOnCard(tester, 'A', '小屋');
    _expectBadgeOnCard(tester, 'B', '箭头');
  });

  testWidgets('同名但身份键不同 → 两张卡都在（不再被静默合并）', (tester) async {
    await _pumpScene(
      tester,
      _spec([
        _figure('user_1', '自绘图形', _tri),
        _figure('user_2', '自绘图形', _arrow),
      ]),
    );

    expect(_cardLabels(tester), <String>[
      '播放自绘图形的对折演示',
      '播放自绘图形的对折演示',
    ], reason: '身份键不同就是两个图形，按名字去重会把教师自绘的第二张吃掉');
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('身份键相同 → 只一张卡（去重按身份键，不按名字）', (tester) async {
    await _pumpScene(
      tester,
      _spec([
        _figure('dup', '房子', _tri),
        _figure('dup', '小屋', _tri),
      ]),
    );

    expect(_cardLabels(tester), <String>['播放房子的对折演示'],
        reason: '同一个图形挂两次角标没有教学意义');
    expect(find.text('B'), findsNothing);
  });

  testWidgets('渲染不消费身份键：内联顶点说了算（不按 key 回查图库）', (tester) async {
    // key 是内置 `house`（图库里 5 个顶点），内联顶点却是三角形。按 key 回查图库
    // 就会画出 5 个顶点——那正是被禁掉的「渲染期回查」（ADR-0083 决策 7）。
    await _pumpScene(tester, _spec([_figure('house', '房子', _tri)]));

    await tester.tap(find.text('房子'));
    await tester.pumpAndSettle();
    final data = tester
        .widget<ReflectionSceneWidget>(
          find.descendant(
            of: find.byType(ShadDialog),
            matching: find.byType(ReflectionSceneWidget),
          ),
        )
        .data;
    expect(data.points, hasLength(3), reason: '几何来自内联顶点，不是 key');
  });

  testWidgets('点卡片仍弹出可拖轴的对折演示（学生侧观感不变）', (tester) async {
    await _pumpScene(tester, _spec([_figure('opt_a', '房子', _tri)]));

    await tester.tap(find.text('房子'));
    await tester.pumpAndSettle();

    expect(find.byType(ShadDialog), findsOneWidget);
    // 3 个轴控制（角度 / 水平 / 垂直）+ 1 个对折进度条：轴仍可拖。
    expect(tester.widgetList<AppSlider>(find.byType(AppSlider)), hasLength(4));
    expect(tester.takeException(), isNull);
  });
}
