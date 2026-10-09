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
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as loc;
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
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/scene_interpreter.dart';

/// 测试桩：只供 [AuthImage] 取 token，避免真去读 shared_preferences（ADR-0077 鉴权看图
/// 后，演示页画廊里有效素材会走 AuthImage，必须覆盖 storageServiceProvider）。
class _FakeStorage extends StorageService {
  @override
  String? getToken() => 'test-token';
}

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
      materials: [
        for (final m in items)
          CoursewareMaterialItem(
            assetId: m['asset_id'] as String,
            caption: m['caption'] as String,
          ),
      ],
    );

CoursewareSectionModel _sceneSection() => CoursewareSectionModel(
      id: 's2',
      kind: CoursewareSectionKind.interactiveScene,
      title: '判断轴对称',
      script: '拖对称轴，看两侧能不能完全重合',
      scene: {
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
  bool reducedMotion = false,
  Size? mediaQuerySize,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // reduced-motion 注入 disableAnimations；mediaQuerySize 注入窗口宽度（T06 字号升档，
  // 因本 harness 下 setSurfaceSize 不反映到 MediaQuery.sizeOf）。
  Widget page = CoursewarePresentPage(coursewareId: courseware.id);
  if (reducedMotion || mediaQuerySize != null) {
    page = MediaQuery(
      data: MediaQueryData(
        size: mediaQuerySize ?? const Size(1366, 768),
        disableAnimations: reducedMotion,
      ),
      child: page,
    );
  }
  final home = Directionality(
    textDirection: TextDirection.ltr,
    child: page,
  );
  await tester.pumpWidget(
    ProviderScope(
      // 数据一律走 provider（R4）：测试不直连 repository / data 层。
      overrides: [
        coursewareDetailProvider(courseware.id).overrideWith((_) => courseware),
        coursewareAssetsProvider.overrideWith((_) => assets),
        storageServiceProvider.overrideWithValue(_FakeStorage()),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          // 与正式 app 一致：CupertinoApp 带 MaterialLocalizations 委托。
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: [
            loc.GlobalMaterialLocalizations.delegate,
            ...GlobalCupertinoLocalizations.delegates,
          ],
          home: home,
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
    expect(find.text('这一环节只有话术'), findsOneWidget);
    expect(find.text('在课件编辑页打开这个环节'), findsOneWidget);
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
    expect(find.text('这一环节只有话术'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('interactive_scene → scene 原样喂 SceneInterpreter', (tester) async {
    final section = _sceneSection();
    await _pumpPresent(tester, courseware: _courseware([section]));

    // 切片 6「零渲染器改动」的执行点：本页不做任何字段翻译，spec 就是顶层 scene 本身。
    final interpreter =
        tester.widget<SceneInterpreter>(find.byType(SceneInterpreter));
    expect(interpreter.kind, 'reflection');
    expect(interpreter.spec, same(section.scene));
    expect(tester.takeException(), isNull);
  });

  testWidgets('无内容环节给降级空态而不是白屏（T03 去 kind 后按内容渲染）',
      (tester) async {
    await _pumpPresent(
      tester,
      courseware: _courseware(const [
        CoursewareSectionModel(id: 'sx', title: '某天新增的环节'),
      ]),
    );

    // T03 去 kind：渲染按内容块，没配任何内容（素材 / 场景 / 练习 / 话术）的环节统一给
    // 「只有话术」空态而非白屏——课堂上白屏等于「课件坏了」。
    expect(find.text('这一环节只有话术'), findsOneWidget);
    expect(find.text('在课件编辑页打开这个环节'), findsOneWidget);
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

  testWidgets('话术多段化（T02）：多段 + 重点逐条投出', (tester) async {
    await _pumpPresent(
      tester,
      courseware: _courseware([
        CoursewareSectionModel(
          id: 's1',
          kind: CoursewareSectionKind.mediaGallery,
          title: '观察素材',
          scriptSegments: [
            CoursewareScriptSegment(
                text: '开场：看图观察', emphasis: CoursewareScriptEmphasis.bold),
            CoursewareScriptSegment(
                text: '追问：共同点？', emphasis: CoursewareScriptEmphasis.highlight),
            const CoursewareScriptSegment(text: '收尾：小结'),
          ],
          payload: {'items': []},
        ),
      ]),
      assets: const [_assetOk],
    );
    // 三段话术都作为提问卡内容逐条出现。
    expect(find.text('开场：看图观察'), findsOneWidget);
    expect(find.text('追问：共同点？'), findsOneWidget);
    expect(find.text('收尾：小结'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧单串话术课件向后兼容（T02）：不空屏、不报错', (tester) async {
    await _pumpPresent(
      tester,
      courseware: _courseware([
        CoursewareSectionModel(
          id: 's2',
          kind: CoursewareSectionKind.mediaGallery,
          title: '旧课件',
          script: '这些图形有什么共同点？',
          payload: {'items': []},
        ),
      ]),
      assets: const [_assetOk],
    );
    expect(find.text('这些图形有什么共同点？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T03 媒体画廊：增删后的项集合在演示页画廊正确呈现', (tester) async {
    const a1 = CoursewareAssetModel(
      id: 'a1',
      name: '蝴蝶标本',
      mime: 'image/png',
      url: '/x/a1',
    );
    const a2 = CoursewareAssetModel(
      id: 'a2',
      name: '建筑立面',
      mime: 'image/png',
      url: '/x/a2',
    );
    await _pumpPresent(
      tester,
      courseware: _courseware([
        _gallerySection([
          {'asset_id': 'a1', 'caption': '蝴蝶标本'},
          {'asset_id': 'a2', 'caption': '建筑立面'},
        ]),
      ]),
      assets: const [a1, a2],
    );
    // 两张有效素材 → 各自 caption 出现，且不应有「素材已移除」占位。
    expect(find.text('蝴蝶标本'), findsOneWidget);
    expect(find.text('建筑立面'), findsOneWidget);
    expect(find.text('素材已移除'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T06 键盘 / 翻页笔翻页与底部按钮完全等价', (tester) async {
    await _pumpPresent(tester, courseware: _fourSections());

    // 生产由 post-frame requestFocus 兜底；测试直接抓 KeyboardListener 节点聚焦更稳。
    final kb =
        tester.widget<KeyboardListener>(find.byType(KeyboardListener));
    kb.focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(kb.focusNode.hasFocus, isTrue, reason: '监听器应已获得焦点');

    expect(find.text('1 / 4'), findsOneWidget);

    // 右方向键 → 下一步。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);

    // 空格 → 下一步（翻页笔下一页键常映射为空格）。
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('3 / 4'), findsOneWidget);

    // 下方向键 → 下一步。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('4 / 4'), findsOneWidget);

    // 末环节：右 / 空格不再越界。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('4 / 4'), findsOneWidget);

    // 左方向键 → 上一步。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('3 / 4'), findsOneWidget);

    // 上方向键 → 上一步（idx 2 → 1，显示 2 / 4）。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);

    // 已在首环节：左 / 上不再越界，停在 1 / 4。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 / 4'), findsOneWidget);
  });

  testWidgets('T06 字号随可用宽度升档（≥1600→1.2, ≥1280→1.1, 否则 1.0）',
      (tester) async {
    final cases = {
      const Size(1920, 1080): 1.2,
      const Size(1366, 768): 1.1,
      const Size(1024, 768): 1.0,
    };
    for (final entry in cases.entries) {
      await _pumpPresent(
        tester,
        courseware: _fourSections(),
        mediaQuerySize: entry.key,
      );
      // 演示页内我加的 MediaQuery 包裹 Column；SafeArea 也会插一个 MediaQuery，但都继承
      // 同一 textScaler。只要树中存在期望档位的 MediaQuery 即说明升档生效。
      final mqs = find
          .descendant(
            of: find.byType(CoursewarePresentPage),
            matching: find.byType(MediaQuery),
          )
          .evaluate()
          .map((e) => (e.widget as MediaQuery).data.textScaler.scale(1.0))
          .toList();
      final matched =
          mqs.any((scale) => (scale - entry.value).abs() < 0.001);
      expect(matched, isTrue,
          reason: '宽度 ${entry.key.width} 应映射到档 ${entry.value}，'
              '实际档位集合 $mqs');
    }
  });

  testWidgets('T06 环节切换加轻过渡；reduced-motion 下退化为瞬时', (tester) async {
    // 非减弱：过渡 200ms。
    await _pumpPresent(tester, courseware: _fourSections());
    final sw = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(sw.duration, const Duration(milliseconds: 200));

    // 切到下一环节触发过渡（仅确认不报错）。
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);

    // reduced-motion：过渡持续时间为零。
    await _pumpPresent(
      tester,
      courseware: _fourSections(),
      reducedMotion: true,
    );
    final swr = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(swr.duration, Duration.zero);
  });
}
