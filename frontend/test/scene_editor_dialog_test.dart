// 教师调参弹窗的布局守卫（ADR-0061 §V/①A 回归）。
//
// 实测过的 bug：把 `editable` 从 false 改成 true（让学生能拖轴）之后，**预览区
// 也长出 3 个轴滑块** —— 而面板上方本来就有同样的 3 个，纯重复；加上预览画布是
// 「边长 = 宽度」的正方形，536 宽的弹窗直接溢出 306px（黄黑条）。
//
// §V 之后：面板用图形画廊选图形（不再在面板里挂轴滑块），轴滑块只在「点图形弹出的
// 对折演示弹窗」里出现。ADR-0083 后 spec 瘦成纯几何 `{kind, points, edges}`——轴初值
// / controls / 文案统一由 kind 外壳提供，故这里钉：
// 1. 弹窗内容**不溢出**（套了 SingleChildScrollView + 画廊替代下拉，预选图形不撑爆）；
// 2. **面板不渲染轴滑块**（它们在弹窗里）——否则白占地方还撑爆弹窗；
// 3. **保存进库的那份是纯几何**（`{kind, points, edges}`，无 editable/title/inputs）。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/domain/repositories/material_repository.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/knowledge_point_scene_editor.dart';
import 'package:kids_learn/features/home/providers/home_provider.dart';
import 'package:kids_learn/features/home/providers/knowledge_manage_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';
import 'package:kids_learn/shared/widgets/app_slider.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';

/// 记录 saveScenes 收到的 spec，用来断言「保存的那份是纯几何」。
class _RecordingManageNotifier extends KnowledgeManageNotifier {
  _RecordingManageNotifier(super.repo);
  List<Map<String, dynamic>>? saved;

  @override
  Future<void> saveScenes(
    String kpId,
    List<Map<String, dynamic>> scenes,
  ) async {
    saved = scenes;
  }
}

class _StubRepo implements MaterialRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 一份合法的「已配置」reflection 模板（新形：图形=房子，纯几何）。
///
/// `pumpEditor` 默认就传它：编辑器仅在「已配置」（`initialScenes` 非空）时才渲染
/// 完整表单（图形画廊 + 保存按钮）；`unconfigured` 时只显示开发者指引（ADR-0061：
/// 交互讲解模板是开发者实现的组件、不是教师在前端手配的），不挂滑块/预览/保存按钮。
const List<Map<String, dynamic>> _configuredScenes = [
  {
    'kind': 'reflection',
    'points': [
      [0.30, 0.70],
      [0.70, 0.70],
      [0.70, 0.45],
      [0.50, 0.25],
      [0.30, 0.45],
    ],
    'edges': [
      [0, 1],
      [1, 2],
      [2, 3],
      [3, 4],
      [4, 0],
    ],
  },
];

void main() {
  Future<void> pumpEditor(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
    List<Map<String, dynamic>>? initialScenes = _configuredScenes,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materialRepositoryProvider.overrideWithValue(_StubRepo()),
          knowledgeManageProvider
              .overrideWith((ref) => _RecordingManageNotifier(_StubRepo())),
        ],
        child: ShadApp.custom(
          theme:
              AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
          appBuilder: (context) => MaterialApp(
            home: CupertinoTheme(
              // 本测试用 MaterialApp 作壳（与真实调用点 CupertinoApp 不同），但产品树
              // 恒提供 CupertinoTheme：AppSlider / AppTheme.colorsOf 经
              // CupertinoTheme.brightnessOf 取亮暗。补这一层，否则预览里的折叠滑块
              // （AppSlider）构建时取不到 CupertinoTheme 而抛错，ReflectionSceneWidget
              // 整棵挂不上。
              data: const CupertinoThemeData(brightness: Brightness.light),
              child: Scaffold(
                // 与真实调用点一致：Dialog + maxWidth 560
                body: Center(
                  child: Dialog(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: KnowledgePointSceneEditor(
                          kpId: 'kp1',
                          kpName: '图形的运动（轴对称）',
                          subject: '数学',
                          grade: 4,
                          semester: '下学期',
                          initialScenes: initialScenes,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 画廊里点开某个图形（按中文名定位卡片）。
  Finder galleryCard(String figureLabel) =>
      find.ancestor(of: find.text(figureLabel), matching: find.byType(AppFocusableAction));

  testWidgets('弹窗内容不溢出（画廊 + 滚动兜底）', (tester) async {
    await pumpEditor(tester);
    expect(tester.takeException(), isNull, reason: '弹窗不应出现 RenderFlex 溢出');
  });

  testWidgets('面板不渲染轴滑块；轴滑块在弹窗内（editable）', (tester) async {
    await pumpEditor(tester);
    // §V：面板用图形画廊选图形，本身**不挂**轴滑块；轴滑块在点图形弹出的弹窗里。
    expect(find.byType(AppSlider), findsNothing,
        reason: '面板不应有轴滑块（§O 的「预览重复滑块」回归）');

    // 点房子 → 弹窗内出现 3 个轴控制 + 1 个对折进度条（共 4 个 AppSlider）。
    await tester.tap(galleryCard('房子'));
    await tester.pumpAndSettle();
    final sliders =
        tester.widgetList<AppSlider>(find.byType(AppSlider)).toList();
    final axisSliders = sliders.where((s) => s.max != null).toList();
    expect(
      axisSliders,
      hasLength(3),
      reason: '弹窗内 3 个轴滑块（角度/水平/垂直）；面板不重复',
    );
  });

  testWidgets('保存的是纯几何 spec（无 editable / title / inputs）', (tester) async {
    await pumpEditor(tester);
    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(KnowledgePointSceneEditor)),
    ).read(knowledgeManageProvider.notifier) as _RecordingManageNotifier;

    // 保存按钮在滚动区下方（弹窗内容比屏高），先滚进视口再点。
    final saveBtn = find.text('保存讲解');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    final spec = notifier.saved!.first;
    expect(spec['kind'], 'reflection');
    // ADR-0083 决策 5：旧字段一概不再出现
    for (final banned in ['editable', 'title', 'inputs', 'controls', 'narrative', 'outputs']) {
      expect(spec.containsKey(banned), isFalse, reason: '不应再有 $banned');
    }
  });

  testWidgets('保存的 spec 带顶层 points + edges（顶点权威，ADR-0061 §O / ADR-0083）',
      (tester) async {
    await pumpEditor(tester);
    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(KnowledgePointSceneEditor)),
    ).read(knowledgeManageProvider.notifier) as _RecordingManageNotifier;

    // 保存按钮在滚动区下方（弹窗内容比屏高），先滚进视口再点。
    final saveBtn = find.text('保存讲解');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    final spec = notifier.saved!.first;
    expect(spec['points'], isA<List>());
    expect((spec['points'] as List).length, greaterThanOrEqualTo(3));
    expect(spec['edges'], isA<List>());
    expect((spec['edges'] as List).length, greaterThanOrEqualTo(3));
  });

  testWidgets('短屏下也不溢出（弹窗高度受限的极端情况）', (tester) async {
    await pumpEditor(tester, size: const Size(700, 560));
    expect(tester.takeException(), isNull);
    // 内容超出时由滚动兜住，而不是溢出报错
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });

  testWidgets('换图形后轴角度跟随该图形默认轴（弹窗内演示同步刷新）', (tester) async {
    // pumpEditor 默认已传 _configuredScenes（编辑器渲染完整表单 + 画廊）。
    await pumpEditor(tester);
    // 点房子：弹窗内演示用房子默认竖轴 90°
    await tester.tap(galleryCard('房子'));
    await tester.pumpAndSettle();
    final axisAngle = tester
        .widget<ReflectionSceneWidget>(
          find.descendant(
            of: find.byType(ShadDialog),
            matching: find.byType(ReflectionSceneWidget),
          ),
        )
        .data
        .axisAngle;
    expect(axisAngle, 90);
  });

  testWidgets('未配置时显示开发者指引、不渲染表单（ADR-0061 §O）', (tester) async {
    // 该知识点尚无模板：编辑器应展示「开发者指引」而非一份误导性的轴对称表单，
    // 且不挂载任何轴滑块 / 保存按钮（模板是开发者实现的组件，非教师前端手配）。
    await pumpEditor(tester, initialScenes: null);
    expect(tester.takeException(), isNull, reason: '未配置分支不应抛异常');
    expect(find.text('尚未配置交互讲解模板（开发者任务）'), findsOneWidget);
    // 表单组件在 unconfigured 下不出现：
    expect(find.text('保存讲解'), findsNothing);
    expect(find.byType(AppSlider), findsNothing);
  });
}
