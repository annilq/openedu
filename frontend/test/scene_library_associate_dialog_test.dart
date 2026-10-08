// T04 补充（ADR-0074）：场景库「关联知识点」对话框改为展示**全部**知识点、可切换解绑。
//
// 钉三件事：
// 1. 已关联本 kind 的知识点不再被过滤：弹窗里仍展示，并标「已关联」勾选态。
// 2. 点按未关联项 → updateKnowledgePointScenes 追加本 kind 的 seed（关联）。
// 3. 点按已关联项 → updateKnowledgePointScenes 移除本 kind 条目、保留其它 kind（解绑）。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/domain/repositories/material_repository.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/scene_library_associate_dialog.dart';
import 'package:kids_learn/features/home/providers/home_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_focusable_action.dart';

/// 目录桩：含三类知识点——已关联本 kind、未关联、关联了其它 kind（解绑须保留）。
class _DialogRepo implements MaterialRepository {
  String? lastKpId;
  List<Map<String, dynamic>>? lastScenes;

  @override
  Future<KnowledgePointScopeList> getKnowledgePointScopes() async =>
      KnowledgePointScopeList(scopes: const [
        KnowledgePointScope(subject: '数学', grade: 4, semester: '上学期', materialCount: 1),
      ]);

  @override
  Future<KnowledgePointDirectory> getKnowledgePointDirectory({
    required String subject,
    required int grade,
    String semester = '',
  }) async =>
      KnowledgePointDirectory(items: [
        // 已关联本 kind（reflection）—— 应仍展示并标「已关联」。
        KnowledgePointOption(
          id: 'kp-a',
          name: '轴对称A',
          scenes: const [
            {'kind': 'reflection', 'title': '轴对称', 'inputs': []},
          ],
        ),
        // 未关联项 —— 点按应追加 reflection seed。
        const KnowledgePointOption(id: 'kp-b', name: '轴对称B'),
        // 关联了 reflection + 其它 kind —— 解绑应只移除 reflection、保留 symmetry。
        KnowledgePointOption(
          id: 'kp-c',
          name: '轴对称C',
          scenes: const [
            {'kind': 'symmetry', 'title': '对称', 'inputs': []},
            {'kind': 'reflection', 'title': '反射', 'inputs': []},
          ],
        ),
      ]);

  @override
  Future<void> updateKnowledgePointScenes({
    required String kpId,
    required List<Map<String, dynamic>> scenes,
  }) async {
    lastKpId = kpId;
    lastScenes = scenes;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

const SceneLibraryEntry _entry = SceneLibraryEntry(
  kind: 'reflection',
  title: '反射',
  defaults: {'inputs': []},
  associatedKnowledgePoints: const [],
  defaultFigureKey: null,
);

Future<void> _pump(WidgetTester tester, _DialogRepo repo,
    {Set<String> associatedIds = const {}}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [materialRepositoryProvider.overrideWithValue(repo)],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => MaterialApp(
          home: ShadToaster(
            child: _Opener(entry: _entry, associatedIds: associatedIds),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // 点「打开」弹出对话框。
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  // 选范围以加载目录。
  await tester.tap(
      find.widgetWithText(AppFocusableAction, '数学 4年级 · 上学期'));
  await tester.pumpAndSettle();
}

/// 测试壳：一个按钮触发公开函数 showAssociateKpDialog（私有对话框类不可在包外引用）。
class _Opener extends StatelessWidget {
  const _Opener({required this.entry, required this.associatedIds});
  final SceneLibraryEntry entry;
  final Set<String> associatedIds;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showAssociateKpDialog(
              context,
              entry: entry,
              associatedIds: associatedIds,
              onAssociated: () {},
            ),
            child: const Text('打开'),
          ),
        ),
      );
}

void main() {
  testWidgets('已关联项不被过滤，仍展示且标「已关联」', (tester) async {
    final repo = _DialogRepo();
    await _pump(tester, repo, associatedIds: {'kp-a'});

    // 三类项都在列表里（未过滤掉已关联的 kp-a）。
    expect(find.text('轴对称A'), findsOneWidget);
    expect(find.text('轴对称B'), findsOneWidget);
    expect(find.text('轴对称C'), findsOneWidget);
    // kp-a 因 associatedIds 含其 id 而处于勾选态。
    expect(find.text('已关联'), findsWidgets);
    // 没有触发任何写回。
    expect(repo.lastKpId, isNull);
  });

  testWidgets('点未关联项 → 追加本 kind 的 seed', (tester) async {
    final repo = _DialogRepo();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(AppFocusableAction, '轴对称B'));
    await tester.pumpAndSettle();

    expect(repo.lastKpId, 'kp-b');
    final scenes = repo.lastScenes!;
    expect(scenes.length, 1);
    expect(scenes.first['kind'], 'reflection');
  });

  testWidgets('点已关联项 → 移除本 kind、解绑', (tester) async {
    final repo = _DialogRepo();
    await _pump(tester, repo, associatedIds: {'kp-a'});

    await tester.tap(find.widgetWithText(AppFocusableAction, '轴对称A'));
    await tester.pumpAndSettle();

    expect(repo.lastKpId, 'kp-a');
    // kp-a 原本仅有 reflection，移除后应为空列表。
    expect(repo.lastScenes, isEmpty);
    // 勾选态翻转：不再显示「已关联」。
    expect(find.text('已关联'), findsNothing);
  });

  testWidgets('解绑保留其它 kind 的场景条目', (tester) async {
    final repo = _DialogRepo();
    await _pump(tester, repo, associatedIds: {'kp-c'});

    await tester.tap(find.widgetWithText(AppFocusableAction, '轴对称C'));
    await tester.pumpAndSettle();

    expect(repo.lastKpId, 'kp-c');
    final scenes = repo.lastScenes!;
    expect(scenes.length, 1);
    expect(scenes.first['kind'], 'symmetry');
  });
}
