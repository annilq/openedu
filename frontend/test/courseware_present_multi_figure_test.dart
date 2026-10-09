// 讲课页端到端贯通（ADR-0076 §2.3 · ticket 05）。
//
// 02 / 03 票各自在画廊 / 解释器接缝上自证，本票从**课件数据**出发：一份带
// `optionGroup` 的 `section.scene` 经真讲课页（CoursewarePresentPage → PresentStage
// → SectionInteractiveScene → SceneInterpreter）走到屏幕上，断言教师在投影上真正
// 看到的那一屏。这条链路上一行业务代码都没改——「零改造」本身就是本票的断言。
//
// 守五件事：
// 1. 三态分派：无图形组 → 单场景；curated → 子集网格；有组无 curated → 整库网格；
// 2. 子集网格的**顺序 == 教师编排顺序**（刻意用逆库序，被重排就红）；
// 3. 只读卡带 play 角标，且**没有任何「是否轴对称」的判定标记**（§2.5 只画不判）；
// 4. 点任意一张 → 弹窗里能旋转 / 平移对称轴，初始轴取**图形自带**默认轴（§2.6）；
// 5. 已有的内容型演示课件（单图、旧 payload 结构）仍渲染单场景，不崩、不变成网格。
//
// 挂载纪律：整树**不套 Material**（根是 ShadApp + CupertinoApp，本仓无 Material
// 祖先）；断言一律**限定在画廊子树内**——讲课页本身还有步骤条药丸等可点区，不限定
// 会把它们一起数进来。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as loc;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/courseware/domain/models/courseware.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_section.dart';
import 'package:kids_learn/features/courseware/presentation/pages/courseware_present_page.dart';
import 'package:kids_learn/features/courseware/providers/courseware_provider.dart';
import 'package:kids_learn/shared/domain/figures.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/widgets/app_slider.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_figure_gallery.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene_data.dart';

/// 课件语境的条目（形状与后端 `extract_option_group` 一致）。
Map<String, dynamic> _item(FigureShape f, {String label = ''}) => {
      'label': label,
      'caption': f.label,
      'figureKey': f.key,
      // 保存时展开写入（红线 2）：渲染层不回查图形库，断网也能摆出来。
      'points': [
        for (final v in f.vertices) <double>[v.x, v.y],
      ],
      'defaultAxisAngle': f.defaultAxisAngle,
    };

/// 教师编排好的一组：**逆库序**（正方形 4 → 箭头 2 → 房子 0）。
///
/// 库序正序的子集在「被重排」与「未被重排」两种实现下渲染结果一样，断言没有牙齿。
Map<String, dynamic> _curatedGroup() => {
      'curated': true,
      'items': [
        _item(kFigureShapes[4]),
        _item(kFigureShapes[2]),
        _item(kFigureShapes[0]),
      ],
    };

/// 题库语境的图形组：有条目但**未声明** curated（缺省 = 整库探索）。
Map<String, dynamic> _plainGroup() => {
      'items': [
        _item(kFigureShapes[0], label: 'A'),
        _item(kFigureShapes[2], label: 'B'),
      ],
    };

/// 一份环节场景：模板轴是 90°（竖轴），用来验证弹窗**不套用**它。
Map<String, dynamic> _spec({Map<String, dynamic>? optionGroup}) => {
      'kind': 'reflection',
      'points': [
        <double>[0.30, 0.70],
        <double>[0.70, 0.70],
        <double>[0.70, 0.45],
        <double>[0.50, 0.25],
        <double>[0.30, 0.45],
      ],
      'controls': {'play': true, 'scrub': true},
      'editable': true,
      'narrative': '拖动对称轴试试看能否完全重合',
      if (optionGroup != null) 'optionGroup': optionGroup,
    };

CoursewareSectionModel _section(
  Map<String, dynamic> scene, {
  Map<String, dynamic>? payload,
}) =>
    CoursewareSectionModel(
      id: 's1',
      title: '一组图形里找对称',
      script: '哪些图形对折后能完全重合？',
      scene: scene,
      payload: payload ?? const {},
    );

CoursewareModel _courseware(CoursewareSectionModel section) => CoursewareModel(
      id: 'cw1',
      subject: '数学',
      grade: 3,
      semester: '下册',
      kpName: '图形的运动（轴对称）',
      title: '轴对称的第一课',
      status: 'ready',
      sections: [section],
    );

Future<void> _pumpPresent(
  WidgetTester tester, {
  required CoursewareModel courseware,
  Size size = const Size(1366, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [coursewareDetailProvider(courseware.id).overrideWith((_) => courseware)],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: [
            loc.GlobalMaterialLocalizations.delegate,
            ...GlobalCupertinoLocalizations.delegates,
          ],
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: CoursewarePresentPage(coursewareId: courseware.id),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 画廊子树内的查找器——讲课页还有步骤条等可点区，不能整页去数。
Finder _inGallery(Finder matching) =>
    find.descendant(of: find.byType(ReflectionFigureGallery), matching: matching);

/// 卡片顺序（树序 == 布局序）：取每张卡的读屏标签，它带图形名。
List<String?> _cardLabels(WidgetTester tester) => tester
    .widgetList<AppFocusableAction>(_inGallery(find.byType(AppFocusableAction)))
    .map((w) => w.semanticLabel)
    .toList();

/// 弹窗里那个场景的数据（初始轴 / 图形名都在上面）。
ReflectionSceneData _dialogScene(WidgetTester tester) => tester
    .widget<ReflectionSceneWidget>(
      find.descendant(of: find.byType(ShadDialog), matching: find.byType(ReflectionSceneWidget)),
    )
    .data;

/// 画廊里出现的所有文本（判「有没有标答案」只看这一屏）。
List<String> _galleryTexts(WidgetTester tester) => tester
    .widgetList<Text>(_inGallery(find.byType(Text)))
    .map((t) => t.data)
    .whereType<String>()
    .toList();

void main() {
  testWidgets('无图形组 → 单场景，讲课页不摆网格', (tester) async {
    await _pumpPresent(tester, courseware: _courseware(_section(_spec())));

    expect(find.byType(ReflectionFigureGallery), findsNothing);
    expect(find.byType(ReflectionSceneWidget), findsOneWidget,
        reason: '单图课件必须仍走今天的单场景路径（用户故事 23）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('curated 图形组 → 摆出 N 张只读卡，顺序 == 教师编排顺序', (tester) async {
    await _pumpPresent(
      tester,
      courseware: _courseware(_section(_spec(optionGroup: _curatedGroup()))),
    );

    expect(find.byType(ReflectionFigureGallery), findsOneWidget);
    expect(find.byType(ReflectionSceneWidget), findsNothing,
        reason: '展示态是只读网格，整块可拖的场景不该直接铺在讲课页上');
    // 逆库序：被「按库序重排」的坏实现会给出 [房子, 箭头, 正方形]。
    expect(_cardLabels(tester), <String>[
      '播放${kFigureShapes[4].label}的对折演示',
      '播放${kFigureShapes[2].label}的对折演示',
      '播放${kFigureShapes[0].label}的对折演示',
    ], reason: '编排顺序就是教学意图，重排等于把意图抹掉');
    expect(tester.takeException(), isNull);
  });

  testWidgets('curated 只读卡：右上角有 play 角标，且无任何「是否对称」判定标记',
      (tester) async {
    await _pumpPresent(
      tester,
      courseware: _courseware(_section(_spec(optionGroup: _curatedGroup()))),
    );

    // 每张卡一个 play 角标（可见性提示，不是唯一命中区）。
    expect(_inGallery(find.byIcon(LucideIcons.play)), findsNWidgets(3));
    // 课件语境没有 A/B/C 选项。
    for (final badge in ['A', 'B', 'C']) {
      expect(_inGallery(find.text(badge)), findsNothing);
    }
    final texts = _galleryTexts(tester);
    expect(
      texts.any((t) => t.contains('轴对称') || t.contains('不对称')),
      isFalse,
      reason: '只读视图标了答案，「点开亲手折」当场死亡（§2.5）：$texts',
    );
    expect(_inGallery(find.byIcon(LucideIcons.check)), findsNothing);
    expect(_inGallery(find.byIcon(LucideIcons.x)), findsNothing);
  });

  testWidgets('有图形组但无 curated → 仍是整库网格 + 选项角标（题库观感不变）',
      (tester) async {
    await _pumpPresent(
      tester,
      courseware: _courseware(_section(_spec(optionGroup: _plainGroup()))),
      size: const Size(1366, 1400),
    );

    final labels = _cardLabels(tester);
    expect(labels, hasLength(kFigureShapes.length),
        reason: '缺省必须仍是整库探索——靠「有条目就裁剪」区分语境会剥夺它');
    expect(labels.first, '播放${kFigureShapes[0].label}的对折演示',
        reason: '带选项标号的仍排在最前');
    expect(_inGallery(find.text('A')), findsOneWidget);
    expect(_inGallery(find.text('B')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点任意一张 → 弹出可操作演示：能旋转 / 平移对称轴，初始轴是图形自带的',
      (tester) async {
    await _pumpPresent(
      tester,
      courseware: _courseware(_section(_spec(optionGroup: _curatedGroup()))),
    );

    final arrow = kFigureShapes[2];
    await tester.tap(_inGallery(find.text(arrow.label)));
    await tester.pumpAndSettle();

    expect(find.byType(ShadDialog), findsOneWidget);
    final data = _dialogScene(tester);
    expect(data.figureLabel, arrow.label);
    expect(data.axisAngle, arrow.defaultAxisAngle,
        reason: '唯一对称轴是横轴的图形一打开就该是横轴，不套用环节的 90°（§2.6）');
    // 3 个轴控制（角度 / 水平 / 垂直）+ 1 个对折进度条：旋转与平移一件不少。
    expect(
      tester.widgetList<AppSlider>(find.byType(AppSlider)),
      hasLength(4),
      reason: '弹窗里必须还能旋转与平移对称轴',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('已有的内容型演示课件（单图 + 旧 payload 结构）仍渲染单场景', (tester) async {
    final spec = _spec();
    await _pumpPresent(
      tester,
      courseware: _courseware(
        // 旧 AI 起草数据把整份 SceneSpec 内嵌在 payload 里，顶层另有 scene：
        // 统一化后渲染只读顶层 scene，legacy payload 不应把它变成网格或空屏。
        _section(spec, payload: Map<String, dynamic>.from(spec)),
      ),
    );

    expect(find.byType(ReflectionFigureGallery), findsNothing);
    expect(find.byType(ReflectionSceneWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
