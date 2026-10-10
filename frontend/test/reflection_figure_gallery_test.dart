// 共享图形画廊（ADR-0076 §2.4 / §2.5）：只读卡右上角的 play 角标 + 保序渲染。
//
// 守四件事：
// 1. 每张只读卡右上角有 play 角标（可见性提示），且与左上角「默认讲解」角标不重叠；
// 2. `preserveOrder: true` 时渲染顺序 == 传入顺序（**用逆序子集断言**：正序子集
//    在库序下也成立，测不出问题）；
// 3. 渲染的就是**调用方给的这一批**（画廊是哑组件，没有「默认整库」，ADR-0083 决策 7）；
// 4. 只读卡上**没有**任何「是否轴对称」的判定标记（§2.5 只画不判）。
//
// 挂载纪律：根是 `ShadApp` + `CupertinoApp`，**不套 Material**——本仓没有 Material
// 祖先，测试里套了就测不出真实构建路径（构建期会抛「No Material widget found」，
// 而 `flutter analyze` 照不出来）。多列布局必须 `setSurfaceSize`，否则父约束把尺寸
// 夹回默认 800×600、误报溢出。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/domain/figures.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_figure_gallery.dart';

import 'support/figure_fixtures.dart';

/// 库序的**逆序**子集：一般四边形 → 正方形 → 房子。
///
/// 为什么必须逆序：正序子集在库序下也成立，排序函数即便没被跳过测试也照样过——
/// 那样的断言守不住「教师编排的顺序不被悄悄重排」。
List<FigureShape> _reverseSubset() => <FigureShape>[
      kQuadGenFixture, // 一般四边形
      kSquareFixture, // 正方形
      kHouseFixture, // 房子
    ];

Future<void> _pumpGallery(
  WidgetTester tester,
  Widget gallery, {
  Size size = const Size(1200, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
      appBuilder: (context) => CupertinoApp(
        // 竖向可滚：画廊若真溢出会在这里暴露为异常，而不是被父约束默默裁掉。
        home: SingleChildScrollView(child: gallery),
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

void main() {
  testWidgets('每张只读卡右上角有 play 角标（默认显示）', (tester) async {
    await _pumpGallery(
      tester,
      ReflectionFigureGallery(figures: _reverseSubset(), onOpen: (_) {}),
    );

    expect(find.byIcon(LucideIcons.play), findsNWidgets(3));
    // 右上角：Positioned 的 right/top 有值、left 无值（与左上角「默认讲解」错开）。
    final badge = tester.widget<Positioned>(
      find.ancestor(
        of: find.byIcon(LucideIcons.play).first,
        matching: find.byType(Positioned),
      ),
    );
    expect(badge.right, isNotNull);
    expect(badge.top, isNotNull);
    expect(badge.left, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('play 角标与左上角「默认讲解」角标不重叠（同一张卡上共存）',
      (tester) async {
    await _pumpGallery(
      tester,
      ReflectionFigureGallery(
        figures: _reverseSubset(),
        selectedKey: 'house',
        onOpen: (_) {},
      ),
    );

    expect(find.byIcon(LucideIcons.play), findsNWidgets(3));
    expect(find.text('默认讲解'), findsOneWidget);

    final playRect = tester.getRect(find.byIcon(LucideIcons.play).last);
    final selectedRect = tester.getRect(find.text('默认讲解'));
    expect(playRect.overlaps(selectedRect), isFalse,
        reason: '两个角标分居右上 / 左上，不得叠在一起');
    expect(tester.takeException(), isNull);
  });

  testWidgets('整卡仍可点（点图形名即触发 onOpen）且读屏标签改写为「播放…」',
      (tester) async {
    final opened = <FigureShape>[];
    await _pumpGallery(
      tester,
      ReflectionFigureGallery(
        figures: _reverseSubset(),
        onOpen: opened.add,
      ),
    );

    await tester.tap(find.text('正方形'));
    await tester.pumpAndSettle();
    expect(opened.single.label, '正方形');

    // 键盘 / 读屏路径：整卡一个语义标签，不再只是「打开」。
    expect(_cardLabels(tester), contains('播放正方形的对折演示'));
    // 用正则：读屏节点会把整卡子树（图形名文字等）并进同一个 label，精确相等匹配不到。
    expect(find.bySemanticsLabel(RegExp('播放正方形的对折演示')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preserveOrder: true → 按传入顺序渲染（逆序子集不被重排）',
      (tester) async {
    await _pumpGallery(
      tester,
      ReflectionFigureGallery(
        figures: _reverseSubset(),
        // 只给房子挂选项角标：若走排序函数，房子会被顶到第一位。
        optionLabels: const <String, String>{'house': 'A'},
        preserveOrder: true,
        onOpen: (_) {},
      ),
    );

    expect(
      _cardLabels(tester),
      <String>[
        '播放一般四边形的对折演示',
        '播放正方形的对折演示',
        '播放房子的对折演示',
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一批数据不传 preserveOrder → 仍走排序函数（选项置顶，回归基线）',
      (tester) async {
    await _pumpGallery(
      tester,
      ReflectionFigureGallery(
        figures: _reverseSubset(),
        optionLabels: const <String, String>{'house': 'A'},
        onOpen: (_) {},
      ),
    );

    // 与上一条正是相反的期望：这条钉住「默认行为一字不变」，也证明上一条的
    // 逆序断言确实有牙齿（排序函数真的会把房子顶到前面）。
    expect(
      _cardLabels(tester),
      <String>[
        '播放房子的对折演示',
        '播放一般四边形的对折演示',
        '播放正方形的对折演示',
      ],
    );
  });

  testWidgets('渲染的就是调用方给的这一批（画廊没有「默认整库」）', (tester) async {
    await _pumpGallery(
      tester,
      ReflectionFigureGallery(
        figures: kTestLibrary,
        optionLabels: const <String, String>{'arrow': 'B'},
        onOpen: (_) {},
      ),
    );

    final labels = _cardLabels(tester);
    expect(labels, hasLength(kTestLibrary.length),
        reason: '画廊是哑组件：给几个画几个，不自己去猜「整库」');
    expect(labels.first, '播放箭头的对折演示', reason: '带选项标号的仍排在最前');
    expect(find.text('B'), findsOneWidget);
    expect(find.byIcon(LucideIcons.play), findsNWidgets(kTestLibrary.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('showPlayBadge: false → 不画 play 角标，整卡照样可点',
      (tester) async {
    final opened = <FigureShape>[];
    await _pumpGallery(
      tester,
      ReflectionFigureGallery(
        figures: _reverseSubset(),
        showPlayBadge: false,
        onOpen: opened.add,
      ),
    );

    expect(find.byIcon(LucideIcons.play), findsNothing);
    await tester.tap(find.text('房子'));
    await tester.pumpAndSettle();
    expect(opened.single.label, '房子');
  });

  testWidgets('只读卡上没有任何「是否轴对称」的判定标记（§2.5 只画不判）',
      (tester) async {
    await _pumpGallery(
      tester,
      ReflectionFigureGallery(
        figures: _reverseSubset(),
        optionLabels: const <String, String>{'house': 'A'},
        preserveOrder: true,
        hint: '点一个图形打开对折演示',
        onOpen: (_) {},
      ),
    );

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    // 「对称轴」是中性词（画廊本来就要画轴），判定标记才会出现「轴对称 / 不对称」。
    expect(texts.any((t) => t.contains('轴对称') || t.contains('不对称')), isFalse,
        reason: '只读视图标了答案，「点开亲手折」当场死亡');
    expect(find.byIcon(LucideIcons.check), findsNothing);
    expect(find.byIcon(LucideIcons.x), findsNothing);
  });
}
