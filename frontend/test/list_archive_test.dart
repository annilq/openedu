// 守住归档的不变量（ADR-0053 P2）。
//
// 三个模块的归档是**三件不同的事**：题库是家长主动弃用（显式、可恢复），任务是
// 时间久远（按月分段，不加字段），错题是系统判定已掌握（毕业打时间戳而非删除）。
// 本文件按模块分组，每组盯各自的语义——这正是「不共用一套 archived 字段」换来的
// 可解释性，测试要把它钉住。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/children/domain/repositories/children_repository.dart';
import 'package:kids_learn/features/children/presentation/providers/children_notifier.dart';
import 'package:kids_learn/features/children/providers/children_provider.dart'
    show childrenNotifierProvider;
import 'package:kids_learn/features/home/data/repositories/question_bank_repository_impl.dart';
import 'package:kids_learn/features/home/domain/repositories/tasks_repository.dart';
import 'package:kids_learn/features/home/presentation/widgets/parent/parent_tasks_view.dart';
import 'package:kids_learn/features/home/providers/home_provider.dart';
import 'package:kids_learn/features/review/data/repositories/review_repository_impl.dart';
import 'package:kids_learn/features/review/presentation/providers/review_notifier.dart';
import 'package:kids_learn/shared/data/remote/network_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/presentation/paging.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 记录查询串的 NetworkService 替身：归档范围 / scope 都是查询参数，
/// 不记下来就只能断言「列表里有几条」，测不出「过滤发生在服务端还是客户端」。
class _RecordingNetwork implements NetworkService {
  final Map<String, dynamic> responses;
  final List<String> gets = [];
  final List<Map<String, dynamic>> posts = [];

  _RecordingNetwork(this.responses);

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final q = (query ?? {})
        .entries
        .map((e) => '${e.key}=${e.value}')
        .toList()
      ..sort();
    gets.add(q.isEmpty ? path : '$path?${q.join('&')}');
    return responses[path];
  }

  @override
  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    posts.add({'path': path, ...?body});
    return responses[path] ?? <String, dynamic>{};
  }

  @override
  Future<dynamic> put(String path,
          {Map<String, dynamic>? query, Map<String, dynamic>? body}) async =>
      null;

  @override
  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async =>
      null;

  @override
  Stream<Uint8List> streamPost(String path,
          {Map<String, dynamic>? body, Duration? receiveTimeout}) =>
      const Stream<Uint8List>.empty();
}

Map<String, dynamic> bankPage(List<Map<String, dynamic>> items) => {
      'items': items,
      'total': items.length,
      'page_size': 20,
    };

Map<String, dynamic> bankItem(String id, {String? archivedAt}) => {
      'id': id,
      'subject': '数学',
      'grade': 2,
      'stem': '题 $id',
      'qtype': 'calc',
      'knowledge_point': '加法',
      'usage_count': 0,
      'archived_at': archivedAt,
    };

void main() {
  group('题库：归档范围在服务端过滤', () {
    test('默认只看在用；切三态时查询参数跟着变', () async {
      final network = _RecordingNetwork({
        '/questions': bankPage([bankItem('q1')]),
      });
      final repo = QuestionBankRepositoryImpl(network);

      await repo.getQuestions();
      await repo.getQuestions(archived: 'archived');
      await repo.getQuestions(archived: 'all');

      expect(network.gets, [
        '/questions?archived=active&page_size=20',
        '/questions?archived=archived&page_size=20',
        '/questions?archived=all&page_size=20',
      ]);
    });

    test('归档与恢复是同一个端点：archived 取反', () async {
      final network = _RecordingNetwork({});
      final repo = QuestionBankRepositoryImpl(network);

      await repo.archiveQuestions(['q1', 'q2'], archived: true);
      await repo.archiveQuestions(['q3'], archived: false);

      expect(network.posts, [
        {
          'path': '/questions/archive',
          'ids': ['q1', 'q2'],
          'archived': true,
        },
        {
          'path': '/questions/archive',
          'ids': ['q3'],
          'archived': false,
        },
      ]);
    });

    test('归档时间解析进模型：已归档的题看得出区别', () async {
      final network = _RecordingNetwork({
        '/questions': bankPage([
          bankItem('q1'),
          bankItem('q2', archivedAt: '2026-09-01T00:00:00'),
        ]),
      });

      final page = await QuestionBankRepositoryImpl(network).getQuestions();

      expect(page.items.first.archivedAt, isNull);
      expect(page.items.last.archivedAt, isNotNull);
    });
  });

  group('错题：已掌握分区', () {
    Map<String, dynamic> wrongPageOf(List<Map<String, dynamic>> items,
            {int graduatedTotal = 0}) =>
        {
          'items': items,
          'total': items.length,
          'page_size': 20,
          'graduated_total': graduatedTotal,
        };

    Map<String, dynamic> wrongItemOf(String id, {String? graduatedAt}) => {
          'id': id,
          'question_id': 'q-$id',
          'subject': '数学',
          'grade': 2,
          'knowledge_point': '加法',
          'qtype': 'calc',
          'stem': '错 $id',
          'answer': '4',
          'wrong_count': 2,
          'review_stage': 1,
          'graduated_at': graduatedAt,
        };

    test('scope=graduated 命中「已掌握」分区，且不污染默认查询', () async {
      final network = _RecordingNetwork({
        '/tasks/children/c1/wrong-questions': wrongPageOf([]),
      });
      final repo = ReviewRepositoryImpl(network);

      await repo.parentWrongQuestions('c1');
      await repo.parentWrongQuestions('c1', scope: 'graduated');

      expect(network.gets, [
        '/tasks/children/c1/wrong-questions?page_size=20&scope=active',
        '/tasks/children/c1/wrong-questions?page_size=20&scope=graduated',
      ]);
    });

    test('「已掌握（N）」取服务端全量计数，不是已加载页的条数', () async {
      final network = _RecordingNetwork({
        '/tasks/children/c1/wrong-questions': wrongPageOf(
          [wrongItemOf('w1')],
          graduatedTotal: 42,
        ),
      });

      final page = await ReviewRepositoryImpl(network).parentWrongQuestions('c1');

      expect(page.graduatedTotal, 42);
      expect(page.items.length, 1, reason: '本页只有 1 条，N 必须是全量');
    });

    test('重新加入复习：清毕业时间戳（后端返回为准）', () async {
      final network = _RecordingNetwork({
        '/tasks/children/c1/wrong-questions/w1/rejoin':
            wrongItemOf('w1'), // 无 graduated_at = 已回到队列
      });

      final rejoined = await ReviewRepositoryImpl(network)
          .rejoinWrongQuestion('c1', 'w1');

      expect(rejoined.graduatedAt, isNull);
      expect(network.posts.single['path'],
          '/tasks/children/c1/wrong-questions/w1/rejoin');
    });

    test('graduatedTotalOf 只对已加载的未毕业列表有意义', () {
      const loaded = PagingLoaded<WrongQuestionModel>(
        WrongQuestionPage(
          items: [],
          total: 0,
          pageSize: 20,
          graduatedTotal: 7,
        ),
      );

      expect(graduatedTotalOf(loaded), 7);
      expect(
        graduatedTotalOf(const PagingLoaded<WrongQuestionModel>(
          CursorPage<WrongQuestionModel>(
              items: [], total: 0, pageSize: 20),
        )),
        0,
      );
      expect(graduatedTotalOf(const PagingLoading<WrongQuestionModel>()), 0);
    });
  });

  group('任务：已完成按月分段', () {
    TaskModel taskOf(String id, DateTime at) => TaskModel(
          id: id,
          title: '任务 $id',
          status: 'done',
          questions: const <QuestionModel>[],
          createdAt: at.toIso8601String(),
        );

    testWidgets('最近 3 个月展开，更早折叠为一行；点开后展开', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 5 个月各一条：前 3 个月展开，后 2 个月折成「…及以前（2）」
      final tasks = <TaskModel>[
        taskOf('t1', DateTime(2026, 9, 10)),
        taskOf('t2', DateTime(2026, 8, 10)),
        taskOf('t3', DateTime(2026, 7, 10)),
        taskOf('t4', DateTime(2026, 6, 10)),
        taskOf('t5', DateTime(2026, 5, 10)),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasksRepositoryProvider
                .overrideWithValue(_StubTasksRepository(tasks)),
            childrenNotifierProvider
                .overrideWith((ref) => _SeededChildrenNotifier(const <UserModel>[])),
          ],
          child: ShadApp.custom(
            theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
            appBuilder: (context) => MaterialApp(
              home: ParentTasksView(
                onNavigateToReview: (_) {},
                onNavigateToCreate: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切到「已完成」
      await tester.tap(find.text('已完成 5'));
      await tester.pumpAndSettle();

      expect(find.text('2026 年 9 月'), findsOneWidget);
      expect(find.text('2026 年 7 月'), findsOneWidget);
      // 更早的两条被折叠：卡片不渲染，只留一行入口
      expect(find.text('任务 t4'), findsNothing);
      expect(find.text('任务 t5'), findsNothing);
      final collapsed = find.textContaining('及以前（2）');
      expect(collapsed, findsOneWidget);

      await tester.tap(collapsed);
      await tester.pumpAndSettle();

      expect(find.text('任务 t4'), findsOneWidget);
      expect(find.text('任务 t5'), findsOneWidget);
      expect(find.textContaining('及以前'), findsNothing);
    });
  });
}

/// 只为构造 notifier 存在；本测试不经它取数。
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
    final counts = _counts();
    if (cursor != null) {
      return TaskPage(
          items: const [], total: 0, pageSize: pageSize, counts: counts);
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
