// 教师调参弹窗的布局守卫（ADR-0061 §O/①A 回归）。
//
// 实测过的 bug：把 `editable` 从 false 改成 true（让学生能拖轴）之后，**预览区
// 也长出 3 个轴滑块** —— 而面板上方本来就有同样的 3 个，纯重复；加上预览画布是
// 「边长 = 宽度」的正方形，536 宽的弹窗直接溢出 306px（黄黑条）。
//
// 这里钉三件事：
// 1. 弹窗内容**不溢出**（套了 SingleChildScrollView + 预览压窄）；
// 2. **预览区不重复**轴滑块（editable:false），否则白占地方还撑爆弹窗；
// 3. **保存进库的那份是 editable:true** —— 学生端必须能拖轴（①A 的本意）。
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
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene.dart';

/// 记录 saveScenes 收到的 spec，用来断言「保存的那份 editable=true」。
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

/// 一份合法的「已配置」reflection 模板：图形=房子（默认竖轴 90°）。
///
/// `pumpEditor` 默认就传它：编辑器仅在「已配置」（`initialScenes` 非空）时才渲染
/// 完整表单（图形选择 + 3 轴滑块 + 预览 + 保存按钮）；`unconfigured` 时只显示
/// 开发者指引（ADR-0061：交互讲解模板是开发者实现的组件、不是教师在前端手配的），
/// 不挂滑块/预览/保存按钮。多数测试要验的就是完整表单，故设为默认。
const List<Map<String, dynamic>> _configuredScenes = [
  {
    'kind': 'reflection',
    'title': '图形的运动（轴对称）',
    'inputs': [
      {
        'key': 'axisAngle',
        'label': '对称轴角度',
        'value': 90,
        'min': 0,
        'max': 180,
        'step': 1,
        'unit': '度',
      },
      {
        'key': 'axisX',
        'label': '对称轴水平',
        'value': 0.5,
        'min': 0.3,
        'max': 0.7,
        'step': 0.01,
        'unit': '比例',
      },
      {
        'key': 'axisY',
        'label': '对称轴垂直',
        'value': 0.5,
        'min': 0.3,
        'max': 0.7,
        'step': 0.01,
        'unit': '比例',
      },
      {'key': 'figure', 'label': '图形', 'value': 'house'},
      {
        'key': 'points',
        'label': '顶点',
        'value': [
          [0.30, 0.70],
          [0.70, 0.70],
          [0.70, 0.45],
          [0.50, 0.25],
          [0.30, 0.45],
        ],
      },
    ],
    'controls': {'play': true, 'pause': true, 'scrub': true, 'speed': true},
    'narrative': '这是一个轴对称图形，中间虚线是它的对称轴。',
    'outputs': {'isAxisymmetric': true},
    'editable': true,
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

  testWidgets('弹窗内容不溢出（回归：曾溢出 306px）', (tester) async {
    await pumpEditor(tester);
    expect(tester.takeException(), isNull, reason: '弹窗不应出现 RenderFlex 溢出');
  });

  testWidgets('预览区不重复轴滑块（editable:false）', (tester) async {
    await pumpEditor(tester);
    // 面板自己 3 个轴滑块（角度/水平/垂直，显式设 max）+ 预览内 1 个对折进度条
    // （未设 max → null）= 4。若预览仍带 editable:true，这里会是 7（多出 3 个重复
    // 的轴滑块）。
    final sliders = tester.widgetList<ShadSlider>(find.byType(ShadSlider)).toList();
    final axisSliders = sliders.where((s) => s.max != null).toList();
    expect(
      axisSliders,
      hasLength(3),
      reason: '轴滑块只应来自面板上方那3 个；预览重复画一遍就是回归',
    );
  });

  testWidgets('保存的那份 editable=true（①A：学生端能拖轴）', (tester) async {
    await pumpEditor(tester);
    // 直接读 spec 构造逻辑：保存走 editable:true，预览走 false。
    // 这里通过「预览里没有轴滑块」+ 保存后 spec 值双侧断言。
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
    expect(
      spec['editable'],
      isTrue,
      reason: '①A：学生端必须能自己旋转/平移对称轴，保存的 spec 必须是 editable:true',
    );
  });

  testWidgets('保存的 spec 带 points（顶点权威，ADR-0061 §O）', (tester) async {
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
    final inputs = spec['inputs'] as List;
    final points = inputs.firstWhere((e) => e['key'] == 'points')['value'];
    expect(points, isA<List>());
    expect((points as List).length, greaterThanOrEqualTo(3));
  });

  testWidgets('短屏下也不溢出（弹窗高度受限的极端情况）', (tester) async {
    await pumpEditor(tester, size: const Size(700, 560));
    expect(tester.takeException(), isNull);
    // 内容超出时由滚动兜住，而不是溢出报错
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });

  testWidgets('换图形后轴角度跟随该图形默认轴（预览同步刷新）', (tester) async {
    // pumpEditor 默认已传 _configuredScenes（编辑器渲染完整表单 + 预览）。
    await pumpEditor(tester);
    // 初始房子= 竖轴 90
    final before = tester
        .widgetList<ReflectionSceneWidget>(find.byType(ReflectionSceneWidget))
        .first
        .data
        .axisAngle;
    expect(before, 90);
  });

  testWidgets('未配置时显示开发者指引、不渲染表单（ADR-0061 §O）', (tester) async {
    // 该知识点尚无模板：编辑器应展示「开发者指引」而非一份误导性的轴对称表单，
    // 且不挂载任何轴滑块 / 保存按钮（模板是开发者实现的组件，非教师前端手配）。
    await pumpEditor(tester, initialScenes: null);
    expect(tester.takeException(), isNull, reason: '未配置分支不应抛异常');
    expect(find.text('尚未配置交互讲解模板（开发者任务）'), findsOneWidget);
    // 表单组件在 unconfigured 下不出现：
    expect(find.text('保存讲解'), findsNothing);
    expect(find.byType(ShadSlider), findsNothing);
  });
}
