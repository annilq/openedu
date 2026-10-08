// T04（ADR-0074）：场景库「关联知识点 / 解除关联 / 按 KP 编辑标题」的回归。
//
// 三件事钉在这里：
// 1. 模型层 `SceneLibraryKpRef.kpMissing` 能从后端 `kp_missing` 解析（恒 false 的预留字段，
//    但前端必须能消费，否则未来显式关联表接入时会整体解析失败）。
// 2. 关联 / 编辑共用的 seed 构造 `buildReflectionSceneSpec` 必须原样透传 title、kind、
//    figureKey、points、editable，否则库里 seed 和编辑器保存会再次镜像漂移。
// 3. 详情页「解除关联」从 `kp.scenes` 移除本 kind、保留其它 kind，并真正打到
//    `updateKnowledgePointScenes`（ADR-0073 快照不变、不级联删场景）。
// 4. 编辑器打开已配置知识点时，标题预填既有 `title`、保存不回退默认名（按 KP 编辑标题）。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/domain/repositories/material_repository.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/knowledge_point_scene_editor.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/scene_library_detail_view.dart';
import 'package:kids_learn/features/home/providers/home_provider.dart';
import 'package:kids_learn/features/home/providers/knowledge_manage_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_inputs.dart';
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene_data.dart';

/// 记录 saveScenes 收到的 spec（编辑器标题测试用）。
class _RecordingManageNotifier extends KnowledgeManageNotifier {
  _RecordingManageNotifier(super.repo);
  List<Map<String, dynamic>>? saved;

  @override
  Future<void> saveScenes(String kpId, List<Map<String, dynamic>> scenes) async {
    saved = scenes;
  }
}

/// 记录 updateKnowledgePointScenes 实参（解除关联测试用）。
class _RecordingRepo implements MaterialRepository {
  String? lastKpId;
  List<Map<String, dynamic>>? lastScenes;

  @override
  Future<void> updateKnowledgePointScenes({
    required String kpId,
    required List<Map<String, dynamic>> scenes,
  }) async {
    lastKpId = kpId;
    lastScenes = scenes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 一份合法 reflection 模板（图形=房子，竖轴 90°），标题故意区别于默认名以便断言预填。
const List<Map<String, dynamic>> _configuredWithCustomTitle = [
  {
    'kind': 'reflection',
    'title': '自定义讲解标题',
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
  // ---- 1. 模型层 kpMissing 解析 ----
  test('SceneLibraryKpRef 解析 kp_missing=true', () {
    final kp = SceneLibraryKpRef.fromJson({
      'id': 'kp1',
      'name': '轴对称',
      'subject': '数学',
      'grade': 4,
      'semester': '下学期',
      'kp_missing': true,
    });
    expect(kp.kpMissing, isTrue);
  });

  test('SceneLibraryKpRef 解析 kp_missing 缺省回落 false（预留字段恒 false）', () {
    final kp = SceneLibraryKpRef.fromJson({
      'id': 'kp1',
      'name': '轴对称',
      'subject': '数学',
      'grade': 4,
      'semester': '下学期',
    });
    expect(kp.kpMissing, isFalse);
  });

  test('SceneLibraryEntry 关联知识点透传 kp_missing', () {
    final e = SceneLibraryEntry.fromJson({
      'kind': 'reflection',
      'title': '轴对称',
      'defaults': <String, dynamic>{},
      'associated_knowledge_points': [
        {
          'id': 'kp1',
          'name': '轴对称',
          'subject': '数学',
          'grade': 4,
          'semester': '下学期',
          'kp_missing': true,
        },
      ],
    });
    expect(e.associatedKnowledgePoints, hasLength(1));
    expect(e.associatedKnowledgePoints.first.kpMissing, isTrue);
  });

  // ---- 2. 关联 / 编辑共用的 seed 构造 ----
  test('buildReflectionSceneSpec 透传 title/kind/figureKey/points/editable', () {
    final spec = buildReflectionSceneSpec(
      kind: 'reflection',
      title: '自定义讲解标题',
      axisAngle: 90,
      axisX: 0.5,
      axisY: 0.5,
      figureKey: 'house',
      points: const [
        [0.3, 0.7],
        [0.7, 0.7],
      ],
      editable: true,
    );
    expect(spec['kind'], 'reflection');
    expect(spec['title'], '自定义讲解标题');
    final inputs = spec['inputs'] as List;
    final figure = inputs.firstWhere((e) => e['key'] == 'figure')['value'];
    expect(figure, 'house');
    final points = inputs.firstWhere((e) => e['key'] == 'points')['value'];
    expect(points, hasLength(2));
    expect(spec['editable'], isTrue);
  });

  // ---- 3. 编辑器：打开已配置知识点预填既有标题，保存不回退默认名 ----
  Future<void> pumpEditor(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
    List<Map<String, dynamic>>? initialScenes = _configuredWithCustomTitle,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _StubRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materialRepositoryProvider.overrideWithValue(repo),
          knowledgeManageProvider
              .overrideWith((ref) => _RecordingManageNotifier(repo)),
        ],
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
          appBuilder: (context) => MaterialApp(
            home: CupertinoTheme(
              data: const CupertinoThemeData(brightness: Brightness.light),
              child: Scaffold(
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

  testWidgets('编辑器打开已配置知识点时预填既有标题、保存不回退默认名',
      (tester) async {
    await pumpEditor(tester);
    // 直接保存：spec 的 title 应等于既有标题（自定义讲解标题），而非默认名。
    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(KnowledgePointSceneEditor)),
    ).read(knowledgeManageProvider.notifier) as _RecordingManageNotifier;

    final saveBtn = find.text('保存讲解');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    final spec = notifier.saved!.first;
    expect(spec['title'], '自定义讲解标题',
        reason: '按 KP 编辑标题：打开已配置知识点应沿用既有标题，不回退默认名');
  });

  testWidgets('编辑器改标题后保存写回新标题', (tester) async {
    await pumpEditor(tester);
    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(KnowledgePointSceneEditor)),
    ).read(knowledgeManageProvider.notifier) as _RecordingManageNotifier;

    // 标题输入框底层是 ShadInput（非裸 TextField），无法直接 find.byType(TextField)。
    // 它把同一个 controller 透传给 AppTextField，故直接驱动该 controller 写回——
    // 与用户键入在「数据层」等价：编辑器 _save 读 _titleController.text 即此对象。
    final tfWidget = tester.widget<AppTextField>(find.byType(AppTextField));
    tfWidget.controller.text = '轴对称入门';
    await tester.pumpAndSettle();

    final saveBtn = find.text('保存讲解');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(notifier.saved!.first['title'], '轴对称入门',
        reason: '教师手改的标题应原样写回 kp.scenes');
  });

  // ---- 4. 详情页「解除关联」：移除本 kind、保留其它 kind、打到 updateKnowledgePointScenes ----
  Future<void> pumpDetail(WidgetTester tester, SceneLibrary library) async {
    final repo = _RecordingRepo();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materialRepositoryProvider.overrideWithValue(repo),
          sceneLibraryProvider.overrideWith((ref) => library),
        ],
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
          appBuilder: (context) => MaterialApp(
            home: ShadToaster(
              child: CupertinoTheme(
                data: const CupertinoThemeData(brightness: Brightness.light),
                child: Scaffold(
                  // 与编辑器弹窗同宽（560）：画廊/预览在此宽度下不溢出（编辑器 7 项测试已证）。
                  body: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: TeacherSceneLibraryDetailView(
                        kind: 'reflection',
                        onBack: () {},
                        onOpenKp: (_) {},
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

  testWidgets('解除关联从 kp.scenes 移除本 kind、保留其它 kind', (tester) async {
    final library = SceneLibrary(
      scenes: [
        SceneLibraryEntry(
          kind: 'reflection',
          title: '轴对称',
          defaults: const <String, dynamic>{},
          associatedKnowledgePoints: [
            SceneLibraryKpRef(
              id: 'kp1',
              name: '轴对称测试',
              subject: '数学',
              grade: 4,
              semester: '下学期',
              scenes: [
                // 首个 = 本 kind（应被移除）；_InstanceCard 只预览首个（140×140 缩略图）。
                Map<String, dynamic>.from(_configuredWithCustomTitle.first),
                // 第二个 = 其它 kind（应被保留）。
                {
                  'kind': 'rotate',
                  'title': '旋转',
                  'inputs': <Map<String, dynamic>>[],
                  'controls': <String, dynamic>{},
                  'narrative': '',
                  'outputs': <String, dynamic>{},
                  'editable': true,
                },
              ],
            ),
          ],
        ),
      ],
    );
    await pumpDetail(tester, library);
    expect(tester.takeException(), isNull, reason: '详情页构建不应抛异常');

    // 点「解除关联」：只此一个 KP，文本唯一。
    await tester.tap(find.text('解除关联'));
    await tester.pumpAndSettle();

    final repo = ProviderScope.containerOf(
      tester.element(find.byType(TeacherSceneLibraryDetailView)),
    ).read(materialRepositoryProvider) as _RecordingRepo;

    expect(repo.lastKpId, 'kp1', reason: '应打到该知识点');
    expect(repo.lastScenes, isNotNull);
    expect(repo.lastScenes, hasLength(1),
        reason: '只保留非 reflection 的场景');
    expect(repo.lastScenes!.first['kind'], 'rotate',
        reason: '本 kind 条目被移除，其它 kind 不受影响（ADR-0073 快照不变）');
  });
}

/// 与 scene_editor_dialog_test 同样的 stub：仅 override 需要的端点，其余抛未实现。
class _StubRepo implements MaterialRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
