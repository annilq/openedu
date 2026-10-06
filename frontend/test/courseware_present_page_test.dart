// 演示页与环节组件（ADR-0067 切片 4b + 5 + 6）。
//
// ⚠️ 刻意**不套 Material**：App 根是 ShadApp + CupertinoApp，整棵树没有 Material
// 祖先，任何 Material 系控件（InkWell / Icons / Scaffold）都会在构建期抛
// 「No Material widget found」——真机上整片页面崩掉，而 `flutter analyze` 照不出来。
// 所以这里照 `assistant_sources_bar_test.dart` 的写法挂 CupertinoApp。
//
// 守四件事：
// 1. 切环节只换主区，步骤条高亮跟着走（§3.8 纪律 3：环节切换在页内完成）；
// 2. `media_gallery` 无素材走空态，**不降级为示意图**（§3.5）；
// 3. 素材 id 失效时显示「素材已移除」，而不是「暂无图片」（§4.2）；
// 4. `interactive_scene` 的 payload 原样喂 SceneInterpreter（切片 6 零渲染器改动）。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/courseware/domain/models/courseware.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_asset.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_section.dart';
import 'package:kids_learn/features/courseware/domain/models/courseware_section_kind.dart';
import 'package:kids_learn/features/courseware/presentation/pages/courseware_present_page.dart';
import 'package:kids_learn/features/courseware/presentation/widgets/courseware_present_step_bar.dart';
import 'package:kids_learn/features/courseware/providers/courseware_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/scene_interpreter.dart';

const _assetOk = CoursewareAssetModel(
  id: 'a1',
  name: 'butterfly.png',
  mime: 'image/png',
  url: '/courseware/assets/a1/file',
);

CoursewareSectionModel _gallerySection(
  List<Map<String, Object>> items, {
  String title = '观察素材',
}) =>
    CoursewareSectionModel(
      id: 's1',
      kind: CoursewareSectionKind.mediaGallery,
      title: title,
      script: '这些图形有什么共同点？',
      payload: {'items': items},
    );

CoursewareSectionModel _sceneSection() => CoursewareSectionModel(
      id: 's2',
      kind: CoursewareSectionKind.interactiveScene,
      title: '判断轴对称',
      script: '拖对称轴，看两侧能不能完全重合',
      payload: {
        'kind': 'reflection',
        'points': [
          [0.30, 0.70],
          [0.70, 0.70],
          [0.70, 0.45],
          [0.50, 0.25],
          [0.30, 0.45],
        ],
        'controls': {'play': true, 'scrub': true},
        'editable': true,
        'narrative': '拖动对称轴试试看能否完全重合',
      },
    );

CoursewareModel _courseware(List<CoursewareSectionModel> sections) =>
    CoursewareModel(
      id: 'cw1',
      subject: '数学',
      grade: 3,
      semester: '下册',
      kpName: '图形的运动（轴对称）',
      title: '轴对称的第一课',
      status: 'ready',
      sections: sections,
    );

/// 四环节课件：素材（空） / 交互 / 练习 / 素材（引用已删素材）。
CoursewareModel _fourSections() => _courseware([
      _gallerySection(const []),
      _sceneSection(),
      CoursewareSectionModel(
        id: 's3',
        kind: CoursewareSectionKind.practice,
        title: '课堂练习',
      ),
      _gallerySection(
        const [
          {'asset_id': 'gone', 'caption': '建筑'}
        ],
        title: '欣赏轴对称之美',
      ),
    ]);

Future<void> _pumpPresent(
  WidgetTester tester, {
  required CoursewareModel courseware,
  List<CoursewareAssetModel> assets = const <CoursewareAssetModel>[],
  Size size = const Size(1366, 768),
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      // 数据一律走 provider（R4）：测试不直连 repository / data 层。
      overrides: [
        coursewareDetailProvider(courseware.id).overrideWith((_) => courseware),
        coursewareAssetsProvider.overrideWith((_) => assets),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: CoursewarePresentPage(coursewareId: courseware.id),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// 步骤条里某个环节的标题（环节标题在步骤条与主区各出现一次，必须限定在步骤条内找）。
///
/// 用它做点击目标：未选中的药丸底色是全透明，[AnimatedContainer] 自身不可命中，
/// 文字节点才是稳定可点的那个。
Finder _chipText(String title) => find.descendant(
      of: find.byType(CoursewarePresentStepBar),
      matching: find.text(title),
    );

/// 步骤条里某个环节的药丸容器（取它的底色判选中态）。
Finder _chip(String title) =>
    find.ancestor(of: _chipText(title), matching: find.byType(AnimatedContainer));

BoxDecoration _chipDecoration(WidgetTester tester, String title) =>
    tester.widget<AnimatedContainer>(_chip(title)).decoration! as BoxDecoration;

/// 切片 8 / §3.7 投影分辨率实测用的课件：11 个环节（素材×多 + 交互 + 练习 + 补充），
/// 首环节带 3 图画廊与超长标题——最易在大屏下触发横向溢出。图统一引用不存在的
/// `missing`，走「素材已移除」占位，避免 widget 测试里跑真实网络图。
CoursewareModel _projectionCourseware() => _courseware([
      _gallerySection(
        [
          {'asset_id': 'missing', 'caption': '蝴蝶标本'},
          {'asset_id': 'missing', 'caption': '建筑立面'},
          {'asset_id': 'missing', 'caption': '剪纸纹样'},
        ],
        title: '观察素材：从生活现象到课本概念的一串很长的标题用来验证投影下不会溢出',
      ),
      _sceneSection(),
      CoursewareSectionModel(
        id: 'sp',
        kind: CoursewareSectionKind.practice,
        title: '课堂练习',
      ),
      for (var i = 0; i < 8; i++)
        _gallerySection(
          [
            {'asset_id': 'missing', 'caption': '补充${i + 1}'}
          ],
          title: '补充环节${i + 1}',
        ),
    ]);

/// 在给定分辨率下渲染演示页，顺序走完所有环节再退回，全程断言无布局溢出。
///
/// 溢出在布局期以 [FlutterError] 上报、被测试框架捕获，[tester.takeException]
/// 取回；任何一步溢出都会让对应断言失败。
Future<void> _checkProjectable(WidgetTester tester, Size size) async {
  await _pumpPresent(
    tester,
    courseware: _projectionCourseware(),
    assets: const <CoursewareAssetModel>[],
    size: size,
  );
  expect(tester.takeException(), isNull,
      reason: '投影分辨率 ${size.width.toInt()}×${size.height.toInt()} 起手不应溢出');
  for (var i = 1; i < 11; i++) {
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: '投影分辨率 $size 走到第 $i 环节不应溢出');
  }
  for (var i = 10; i > 0; i--) {
    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: '投影分辨率 $size 退回第 $i 环节不应溢出');
  }
}

void main() {
  testWidgets('四区都在：标题 + 元信息 + 步骤条 + 主区 + 2 / 4', (tester) async {
    await _pumpPresent(tester, courseware: _fourSections());

    expect(find.text('轴对称的第一课'), findsOneWidget);
    expect(find.text('数学 · 3年级 · 下册'), findsOneWidget);
    expect(find.text('退出演示'), findsOneWidget);
    // 话术当提问卡直接投给学生（决策 15）：不折叠、不做仅教师可见。
    expect(find.text('这些图形有什么共同点？'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);
  });

  testWidgets('点步骤条切环节：只换主区，步骤条高亮跟着走', (tester) async {
    await _pumpPresent(tester, courseware: _fourSections());

    final app =
        AppTheme.colorsOf(tester.element(find.byType(CoursewarePresentStepBar)));

    // 起手在第 1 环节。
    expect(_chipDecoration(tester, '观察素材').color, app.surfaceActive);
    expect(_chipDecoration(tester, '判断轴对称').color, isNot(app.surfaceActive));
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.byType(SceneInterpreter), findsNothing);

    // 点第 2 环节：主区换成交互演示，其余三区不动。
    await tester.tap(_chipText('判断轴对称'));
    await tester.pumpAndSettle();

    expect(find.byType(SceneInterpreter), findsOneWidget);
    expect(find.text('2 / 4'), findsOneWidget);
    // 步骤条高亮搬到了第 2 项，第 1 项退出选中态。
    expect(_chipDecoration(tester, '判断轴对称').color, app.surfaceActive);
    expect(_chipDecoration(tester, '观察素材').color, isNot(app.surfaceActive));
    // 头部与步骤条是四区里的固定区，切环节不动它们。
    expect(find.text('轴对称的第一课'), findsOneWidget);
    expect(_chip('观察素材'), findsOneWidget);
    expect(_chip('欣赏轴对称之美'), findsOneWidget);
  });

  testWidgets('底部「下一步」推进环节，「上一步」退回', (tester) async {
    await _pumpPresent(tester, courseware: _fourSections());

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);

    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 4'), findsOneWidget);
  });

  testWidgets('media_gallery 无素材 → 空态 + 上传引导，不降级为示意图',
      (tester) async {
    await _pumpPresent(
      tester,
      courseware: _courseware([_gallerySection(const [])]),
      assets: const [_assetOk],
    );

    // 空态必须回答「为什么空」+「下一步做什么」（ADR-0051）。
    expect(find.text('这一环节还没有素材'), findsOneWidget);
    expect(find.text('在课件编辑页上传这一环节要用的图片'), findsOneWidget);
    // ⚠️ 关键断言：没有示意图。§3.5 明确禁止降级到顶点图库示意图形——
    // 偷偷降级就是把「没有素材」伪装成「有内容」。
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('素材 id 在素材库里找不到 → 「素材已移除」占位', (tester) async {
    await _pumpPresent(
      tester,
      courseware: _courseware([
        _gallerySection(const [
          {'asset_id': 'gone', 'caption': '建筑'}
        ]),
      ]),
      assets: const [_assetOk],
    );

    // §4.2（决策 10 允许删素材）：引用留下、素材没了 → 占位，且与空态文案不同。
    expect(find.text('素材已移除'), findsOneWidget);
    expect(find.text('这一环节还没有素材'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('interactive_scene → payload 原样喂 SceneInterpreter',
      (tester) async {
    final section = _sceneSection();
    await _pumpPresent(tester, courseware: _courseware([section]));

    // 切片 6「零渲染器改动」的执行点：本页不做任何字段翻译，spec 就是 payload 本身。
    final interpreter =
        tester.widget<SceneInterpreter>(find.byType(SceneInterpreter));
    expect(interpreter.kind, 'reflection');
    expect(interpreter.spec, same(section.payload));
    expect(tester.takeException(), isNull);
  });

  testWidgets('未知 kind 给降级提示而不是白屏', (tester) async {
    await _pumpPresent(
      tester,
      courseware: _courseware(const [
        CoursewareSectionModel(id: 'sx', title: '某天新增的环节'),
      ]),
    );

    expect(find.text('暂不支持的环节类型'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('投影分辨率 1920×1080 不溢出（切片 8 / §3.7）', (tester) async {
    await _checkProjectable(tester, const Size(1920, 1080));
  });

  testWidgets('投影分辨率 1366×768 不溢出（切片 8 / §3.7）', (tester) async {
    await _checkProjectable(tester, const Size(1366, 768));
  });

  testWidgets('平板 1024×768 不溢出（切片 8 / §3.7）', (tester) async {
    await _checkProjectable(tester, const Size(1024, 768));
  });
}
