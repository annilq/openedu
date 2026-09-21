// 守住「任务」空态的设计契约。
//
// 背景：三个 Tab 原本共用一句「暂无{草稿/进行中/已完成}任务」+ 一个 40px 图标，
// 贴在上左角（`Align(topLeft)`）：用户知道没有，但不知道为什么空、下一步点哪。
// 同时概览页的「最近任务」空态退化成一行灰字，与「加载失败」在视觉上不可区分。
// 这些都不是类型错误，`flutter analyze` 照不出，只能守行为。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/children/domain/repositories/children_repository.dart';
import 'package:kids_learn/features/children/presentation/providers/children_notifier.dart';
import 'package:kids_learn/features/children/providers/children_provider.dart'
    show childrenNotifierProvider;
import 'package:kids_learn/features/home/domain/repositories/tasks_repository.dart';
import 'package:kids_learn/features/home/presentation/providers/selected_child_provider.dart';
import 'package:kids_learn/features/home/presentation/widgets/parent/parent_overview_view.dart';
import 'package:kids_learn/features/home/presentation/widgets/parent/parent_tasks_view.dart';
import 'package:kids_learn/features/home/providers/home_provider.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_empty_state.dart';
import 'package:kids_learn/shared/widgets/app_card.dart';

/// 只为构造 notifier 存在；本测试不经它取数（状态由仓库桩直接返回）。
class _UnusedChildrenRepo implements ChildrenRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SeededChildrenNotifier extends ChildrenNotifier {
  _SeededChildrenNotifier(List<UserModel> children)
      : super(_UnusedChildrenRepo()) {
    state = ChildrenLoaded(children);
  }
}

class _StubTasksRepository implements TasksRepository {
  _StubTasksRepository(this.parent);
  final List<TaskModel> parent;

  @override
  Future<TaskPage> parentTasks({
    String? status,
    String? cursor,
    int pageSize = 20,
  }) async {
    // 计数与过滤都在「服务端」：徽标必须是全量计数，不能是已加载页的计数。
    final counts = _counts();
    if (cursor != null) {
      return TaskPage(items: const [], total: 0, pageSize: pageSize, counts: counts);
    }
    final items = status == null || status.isEmpty
        ? parent
        : parent.where((t) => status.split(',').contains(t.status)).toList();
    return TaskPage(
      items: items.take(pageSize).toList(),
      total: items.length,
      pageSize: pageSize,
      counts: counts,
    );
  }

  TaskCounts _counts() => TaskCounts(
        draft: parent.where((t) => t.status == 'draft').length,
        ready: parent.where((t) => t.status == 'ready').length,
        assigned: parent.where((t) => t.status == 'assigned').length,
        done: parent.where((t) => t.status == 'done').length,
      );

  @override
  Future<List<TaskModel>> todayTasks() async => const <TaskModel>[];

  @override
  Future<ProgressModel> progress(String childId) async => ProgressModel(
        childId: childId,
        total: 0,
        correct: 0,
        accuracy: 0,
        streakDays: 0,
        checkinDays: 0,
      );

  @override
  Future<MasteryModel> mastery(String childId) async => MasteryModel(
        childId: childId,
        totalKnowledgePoints: 0,
        masteredCount: 0,
        items: const <KnowledgeMasteryModel>[],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TaskModel _task(String id, String status) => TaskModel(
      id: id,
      title: '任务 $id',
      status: status,
      questions: const <QuestionModel>[],
    );

void main() {
  Future<void> pumpTasks(
    WidgetTester tester,
    List<TaskModel> tasks, {
    VoidCallback? onCreate,
    Size size = const Size(900, 800),
  }) async {
    // 必须显式设视口：test surface 默认 800×600，`SizedBox(width: ...)` 会被静默裁掉。
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(_StubTasksRepository(tasks)),
          childrenNotifierProvider
              .overrideWith((ref) => _SeededChildrenNotifier(const <UserModel>[])),
        ],
        child: ShadApp.custom(
          // 断言几何必须传真实主题：不传会走 shadcn 默认主题，量出来的尺寸与产品不符。
          theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => MaterialApp(
            home: ParentTasksView(
              onNavigateToReview: (_) {},
              onNavigateToCreate: onCreate,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('首次空（一个任务都没有）：讲流程 + 给出入口', (tester) async {
    var createTaps = 0;
    await pumpTasks(tester, const <TaskModel>[], onCreate: () => createTaps++);

    expect(find.text('还没有布置过任务'), findsOneWidget);
    // 流程说明：用户还没跑通过流程，空态要替产品把流程讲一遍。
    for (final step in const [
      '选学科与知识点，让 AI 出题',
      '复核题目、删掉不合适的',
      '派给娃娃，完成后自动归档',
    ]) {
      expect(find.text(step), findsOneWidget);
    }

    await tester.tap(find.text('去布置任务'));
    await tester.pumpAndSettle();
    expect(createTaps, 1, reason: '空态必须给出出口，否则用户不知道下一步点哪');
  });

  testWidgets('只有当前 Tab 空：指路到真正有数据的 Tab，不送进另一个空页', (tester) async {
    // 只有一条「已完成」→ 进行中 Tab 为空，但草稿也是 0，指路必须是「查看已完成」。
    await pumpTasks(tester, <TaskModel>[_task('t1', 'done')]);

    await tester.tap(find.text('进行中 0'));
    await tester.pumpAndSettle();

    expect(find.text('没有进行中的任务'), findsOneWidget);
    expect(find.text('任务都已完成。娃娃做完后会自动归档到「已完成」。'),
        findsOneWidget);
    expect(find.text('去派发草稿'), findsNothing,
        reason: '草稿也是 0，把用户指过去等于送进第二个空页');

    await tester.tap(find.text('查看已完成'));
    await tester.pumpAndSettle();
    expect(find.text('任务 t1'), findsOneWidget, reason: '指路后要真的落到有数据的 Tab');
  });

  testWidgets('空态居中且宽度收口（不再贴左上角）', (tester) async {
    await pumpTasks(tester, const <TaskModel>[]);

    // 88 色块与标题都居中：旧实现用 `Align(topLeft)`，色块左缘贴着列表区左边。
    const areaCenter = 900 / 2;
    final icon = tester.getRect(find.byIcon(LucideIcons.notebookPen));
    expect(icon.center.dx, closeTo(areaCenter, 1));

    final title = tester.getRect(find.text('还没有布置过任务'));
    expect(title.center.dx, closeTo(areaCenter, 1));
    // 说明文字不拉成长行：宽度收口 AppLayout.contentEmpty(440)。
    // +1 是给文本排版的子像素舍入（实测 440.0019）。
    final message = tester.getRect(find.textContaining('按学科与知识点'));
    expect(message.width, lessThanOrEqualTo(AppLayout.contentEmpty + 1));
  });

  testWidgets('两种变体的几何与强调态前景', (tester) async {
    await tester.pumpWidget(
      ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
        appBuilder: (context) => MaterialApp(
          home: const Column(
            children: [
              AppEmptyState(
                icon: LucideIcons.sun,
                title: '完整版',
                message: '88 色块 / 44 图标',
                tone: AppBrutal.yellow,
              ),
              AppEmptyState.inline(
                icon: LucideIcons.sun,
                title: '内联版',
                message: '48 色块 / 24 图标',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final icons = tester.widgetList<Icon>(find.byIcon(LucideIcons.sun)).toList();
    expect(icons.length, 2);
    expect(icons[0].size, 44, reason: '完整版与 AppError 同骨架（88 色块）');
    expect(icons[1].size, 24, reason: '内联版是内容流里的一行，不能抢重量');
    // 撞色底必须配 AppBrutal.onColor（这里是 ink），否则亮块配浅字不达标。
    expect(icons[0].color, AppBrutal.ink);
    expect(icons[1].color, isNot(AppBrutal.ink));
  });

  testWidgets('概览「最近任务」空态有边界与出口（不再是一行灰字）', (tester) async {
    var createTaps = 0;
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasksRepositoryProvider
              .overrideWithValue(_StubTasksRepository(const <TaskModel>[])),
          childrenNotifierProvider
              .overrideWith((ref) => _SeededChildrenNotifier(const <UserModel>[])),
          selectedChildProvider.overrideWith((ref) {
            final notifier = SelectedChildNotifier(ref);
            // 直接种状态：走 select() 会触发四个 load，与本测试无关。
            notifier.state = const SelectedChild(id: 'c1', grade: 2);
            return notifier;
          }),
        ],
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => MaterialApp(
            home: ParentOverviewView(
              onNavigateToReview: (_) {},
              onNavigateToCreate: () => createTaps++,
            ),
          ),
        ),
      ),
    );
    // 不能用 pumpAndSettle：概览页的骨架屏是无限循环动画，settle 永远等不到静默。
    // 三帧足够：首帧 → postFrame 触发 load → 异步返回 → Loaded 重绘。
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('还没有任务记录'), findsOneWidget);
    expect(find.text('布置任务后，最近 4 条会显示在这里。'), findsOneWidget);
    // 有边界：空态落在卡片里，与「加载失败」可区分（灰字做不到）。
    expect(find.ancestor(of: find.text('还没有任务记录'), matching: find.byType(AppCard)),
        findsOneWidget);

    await tester.tap(find.text('去布置任务'));
    await tester.pump();
    expect(createTaps, 1);
  });
}
