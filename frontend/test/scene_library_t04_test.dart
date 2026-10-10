// T04（ADR-0074 / ADR-0083）：场景库「关联知识点 / 解除关联 / 编辑器 seed」的回归。
//
// 三件事钉在这里：
// 1. 模型层 `SceneLibraryKpRef.kpMissing` 能从后端 `kp_missing` 解析（恒 false 的预留
//    字段，但前端必须能消费，否则未来显式关联表接入时会整体解析失败）。
// 2. 关联 / 编辑共用的 seed 构造 `buildReflectionSceneSpec` 产出**纯几何**
//    `{kind, points, edges}`（ADR-0083 决策 5：title/inputs/controls 等已删）。
// 3. 详情页「解除关联」从 `kp.scenes` 移除本 kind、保留其它 kind，并真正打到
//    `updateKnowledgePointScenes`（ADR-0073 快照不变、不级联删场景）。
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
import 'package:kids_learn/shared/widgets/scene_interpreter/reflection_scene_data.dart';

/// 记录 saveScenes 收到的 spec（编辑器回归用）。
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

/// 一份合法 reflection 模板（新形：图形=房子，纯几何）。
const List<Map<String, dynamic>> _configuredReflection = [
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

  // ---- 2. 关联 / 编辑共用的 seed 构造（ADR-0083：纯几何） ----
  test('buildReflectionSceneSpec 产出纯几何 {kind, points, edges}', () {
    final spec = buildReflectionSceneSpec(
      kind: 'reflection',
      points: const [
        [0.3, 0.7],
        [0.7, 0.7],
        [0.5, 0.3],
      ],
    );
    expect(spec['kind'], 'reflection');
    expect(spec['points'], hasLength(3));
    // 默认按顶点顺序闭合
    expect(spec['edges'], [
      [0, 1],
      [1, 2],
      [2, 0],
    ]);
    // 旧字段一概不再出现（ADR-0083 决策 5）
    for (final banned in ['title', 'inputs', 'controls', 'narrative', 'outputs', 'editable']) {
      expect(spec.containsKey(banned), isFalse, reason: '不应再有 $banned');
    }
  });

  // ---- 3. 编辑器：打开已配置知识点 → 保存产出纯几何 spec（几何与配置一致） ----
  Future<void> pumpEditor(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
    List<Map<String, dynamic>>? initialScenes = _configuredReflection,
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

  testWidgets('编辑器保存产出纯几何 spec（kind + 配置图形的顶点）', (tester) async {
    await pumpEditor(tester);
    final notifier = ProviderScope.containerOf(
      tester.element(find.byType(KnowledgePointSceneEditor)),
    ).read(knowledgeManageProvider.notifier) as _RecordingManageNotifier;

    final saveBtn = find.text('保存讲解');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    final spec = notifier.saved!.first;
    expect(spec['kind'], 'reflection');
    // 回显到房子（配置的图形），顶点逐点一致
    expect(spec['points'], [
      [0.30, 0.70],
      [0.70, 0.70],
      [0.70, 0.45],
      [0.50, 0.25],
      [0.30, 0.45],
    ]);
    expect(spec['edges'], hasLength(5));
    expect(spec.containsKey('title'), isFalse);
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
                  // 与编辑器弹窗同宽（560）：画廊/预览在此宽度下不溢出。
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
                // 首个 = 本 kind（应被移除）。
                Map<String, dynamic>.from(_configuredReflection.first),
                // 第二个 = 其它 kind（应被保留）。
                {
                  'kind': 'rotate',
                  'points': <List<double>>[],
                  'edges': <List<int>>[],
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
