// ADR-0088 / ticket 02：独立「运行轨迹」页——与历史会话气泡**并列**的第二个消费者。
//
// 断言的是**两种投影的口径分叉**，不是「页面上有没有某个组件」：
// - 运行轨迹页渲染一次运行的**全步骤**（routing / tool_call / tool_result / output）
//   以及每步的 model / token / 延迟；
// - 这些步骤**不进历史气泡**（轨迹页里没有气泡投影 `AssistantMessageList`，也不
//   落到助手页 `AssistantChatPage`）——否则教师会在「跟 AI 聊天」的上下文里读到
//   路由决策与工具载荷，两个视角互相污染；
// - 入口分离且导航单源：侧栏「运行轨迹」经 HomeScreen 的同一个 `_go` 打开本页，
//   高亮唯一。
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/repositories/run_trace_repository.dart';
import 'package:kids_learn/features/assistant/domain/run_trace.dart';
import 'package:kids_learn/features/assistant/presentation/screens/assistant_chat_page.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_message_list.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/run_trace_detail_view.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/run_trace_view.dart';
import 'package:kids_learn/features/assistant/providers/run_trace_provider.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/features/home/presentation/screens/home_screen.dart';
import 'package:kids_learn/features/students/providers/students_provider.dart';
import 'package:kids_learn/shared/data/local/storage_service.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/domain/providers/core_providers.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_actions.dart' show AppIconAction;
import 'package:kids_learn/shared/widgets/app_sidebar.dart' show AppSidebarItem;

const _run = RunTraceRun(
  id: 'r1',
  kind: 'query',
  title: '查询题库中的题目',
  model: 'gemini-2.0-flash',
  status: 'done',
  createdAt: '2026-10-12T09:00:00+08:00',
);

/// 一次多步运行：input / routing / tool_call / tool_result / output 五步齐全。
const _detail = RunTraceDetail(
  run: _run,
  steps: [
    RunTraceStep(
      id: 'm1',
      turn: 0,
      role: 'user',
      step: 'input',
      content: '查询题库中的题目',
    ),
    RunTraceStep(
      id: 'm2',
      turn: 1,
      role: 'assistant',
      step: 'routing',
      content: '决定调用 list_bank_questions',
      model: 'gemini-2.0-flash',
      latencyMs: 210,
      usage: StepUsage(prompt: 120, completion: 8, total: 128),
    ),
    RunTraceStep(
      id: 'm3',
      turn: 2,
      role: 'assistant',
      step: 'tool_call',
      content: 'list_bank_questions(subject=数学)',
      model: 'gemini-2.0-flash',
      latencyMs: 95,
      usage: StepUsage(prompt: 60, completion: 24, total: 84),
    ),
    RunTraceStep(
      id: 'm4',
      turn: 3,
      role: 'tool',
      step: 'tool_result',
      content: '命中 12 道题',
      model: 'gemini-2.0-flash',
      latencyMs: 1240,
      usage: StepUsage(prompt: 0, completion: 180, total: 180),
    ),
    RunTraceStep(
      id: 'm5',
      turn: 4,
      role: 'assistant',
      step: 'output',
      content: '题库里共查到 12 道数学题。',
      model: 'gemini-2.0-flash',
      latencyMs: 1830,
      usage: StepUsage(prompt: 300, completion: 220, total: 520),
    ),
  ],
);

/// 01 还没写值时（usage / latency_ms / model 全空）也不许崩——列显示占位。
const _bareDetail = RunTraceDetail(
  run: RunTraceRun(id: 'r2', kind: 'query', title: '早期运行', status: 'done'),
  steps: [
    RunTraceStep(id: 'b1', turn: 0, role: 'user', step: 'input', content: '你好'),
    RunTraceStep(id: 'b2', turn: 1, role: 'assistant', step: 'output', content: '在的'),
  ],
);

class _FakeRunTraceRepo implements RunTraceRepository {
  _FakeRunTraceRepo({this.items = const [_run], this.fail = false});

  final List<RunTraceRun> items;
  final bool fail;
  final List<String> opened = [];

  @override
  Future<List<RunTraceRun>> runs() async {
    if (fail) throw StateError('403 越权');
    return items;
  }

  @override
  Future<RunTraceDetail> detail(String runId) async {
    opened.add(runId);
    if (fail) throw StateError('403 越权');
    return runId == 'r2' ? _bareDetail : _detail;
  }

  @override
  Future<RunTraceDetail> reveal(String runId, String reason) async {
    opened.add(runId);
    return runId == 'r2' ? _bareDetail : _detail;
  }
}

void main() {
  group('运行轨迹列表', () {
    testWidgets('渲染一次运行（标题 + 类型 + 时间），可点开', (tester) async {
      await _pumpList(tester, repo: _FakeRunTraceRepo());

      expect(find.text('查询题库中的题目'), findsOneWidget);
      // kind 翻成教师口径的中文标签（后端 kind 是开放字符串，只作标签）。
      expect(find.textContaining('答疑'), findsOneWidget);
      // 时间按本地时区格式化（fixture 是 +08:00，任何时区都落在 10-12 当天）。
      expect(find.textContaining('10-12'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('运行轨迹详情：全步骤 + 步级元数据（ADR-0088 §2.3）', () {
    testWidgets('一次运行的五类步骤全部渲染，且每步带 model / token / 延迟',
        (tester) async {
      await _pumpDetail(tester, 'r1');

      // 五类步骤必须可见——气泡投影里 input 之后的内部步骤是被剥掉的，
      // 这里正是本页的全部价值。
      for (final step in const [
        'input',
        'routing',
        'tool_call',
        'tool_result',
        'output'
      ]) {
        expect(find.text(step), findsWidgets,
            reason: '运行轨迹页必须渲染 $step 步（审计 / 排障视角的全步骤投影）');
      }
      // 步级元数据：模型、token、延迟。
      expect(find.textContaining('128 token'), findsOneWidget,
          reason: 'routing 步应显示本步 token（01 落库值）');
      expect(find.textContaining('210 ms'), findsOneWidget,
          reason: 'routing 步应显示本步延迟');
      expect(find.textContaining('520 token'), findsOneWidget,
          reason: 'output 步应显示本步 token');
      expect(find.textContaining('1830 ms'), findsOneWidget,
          reason: 'output 步应显示本步延迟');
      expect(find.textContaining('gemini-2.0-flash'), findsWidgets,
          reason: '每步应显示本步模型');
      expect(tester.takeException(), isNull);
    });

    testWidgets('01 无值时对应列显示占位，不崩溃', (tester) async {
      await _pumpDetail(tester, 'r2');

      expect(find.text('output'), findsWidgets);
      expect(find.textContaining('token 未记录'), findsWidgets,
          reason: 'usage 为空时显示占位而非崩溃 / 显示 0');
      expect(find.textContaining('模型未记录'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('取数失败（越权 / 无权限）给出失败态与重试出口，不白屏',
        (tester) async {
      await _pumpDetail(tester, 'r1', repo: _FakeRunTraceRepo(fail: true));

      expect(find.textContaining('运行轨迹读取失败'), findsOneWidget,
          reason: '权限不足 / 取数失败必须有可读的失败态，而不是空白页');
      expect(tester.takeException(), isNull);
    });

    testWidgets('会话级合计：token 与耗时由步级上推（ADR-0088 §2.5）',
        (tester) async {
      await _pumpDetail(tester, 'r1');

      // 912 = 128+84+180+520；3375 = 210+95+1240+1830。
      expect(find.textContaining('912 token'), findsOneWidget,
          reason: '会话级 token 由步级 usage 上推，不建汇总列');
      expect(find.textContaining('3375 ms'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('列表空态', () {
    testWidgets('没有运行记录时给出空态，而不是空白页', (tester) async {
      await _pumpList(tester, repo: _FakeRunTraceRepo(items: const []));

      expect(find.textContaining('还没有 AI 运行记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('列表取数失败（越权 / 无权限）给出失败态与重试出口，不白屏',
        (tester) async {
      await _pumpList(tester, repo: _FakeRunTraceRepo(fail: true));

      expect(find.textContaining('运行轨迹读取失败'), findsOneWidget,
          reason: '权限不足 / 取数失败必须有可读的失败态，而不是空白页');
      expect(tester.takeException(), isNull);
    });
  });

  group('双消费者分叉：轨迹不进历史气泡（ADR-0088 §2.3）', () {
    testWidgets('轨迹页不渲染气泡投影，也不落到助手页', (tester) async {
      await _pumpDetail(tester, 'r1');

      expect(find.byType(AssistantMessageList), findsNothing,
          reason: '运行轨迹是「全步骤 + 元数据」投影，不得复用历史会话的气泡投影');
      expect(find.byType(AssistantChatPage), findsNothing,
          reason: '轨迹页与历史会话 / 助手页是两个入口，点开轨迹不进助手页');
      expect(tester.takeException(), isNull);
    });

    test('静态：轨迹页源码不引用气泡投影与历史会话 provider', () {
      for (final file in const [
        'lib/features/assistant/presentation/widgets/run_trace_view.dart',
        'lib/features/assistant/presentation/widgets/run_trace_detail_view.dart',
      ]) {
        final src = File(file).readAsStringSync();
        for (final banned in const [
          'AssistantMessageList',
          'conversationHistoryProvider',
          'AssistantBubble',
        ]) {
          expect(src.contains(banned), isFalse,
              reason: '$file 不得引用 $banned：轨迹口径与气泡口径必须各自独立，'
                  '混用会派生出「第三套步骤→气泡」逻辑');
        }
      }
    });
  });

  group('入口分离 + 导航单源（ADR-0059）', () {
    testWidgets('侧栏「运行轨迹」高亮唯一并渲染轨迹列表，点开一条进详情',
        (tester) async {
      await _pumpTeacherHome(tester, repo: _FakeRunTraceRepo());

      expect(_activeLabels(tester), ['概览']);

      await tester.tap(find.text('运行轨迹'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_activeLabels(tester), ['运行轨迹'],
          reason: '同一时刻侧栏只能有一个高亮项（单一导航状态）');
      expect(find.textContaining('查询题库中的题目'), findsWidgets,
          reason: '轨迹列表应渲染一次运行');

      await tester.tap(find.textContaining('查询题库中的题目'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('tool_result'), findsWidgets,
          reason: '点开一次运行应进轨迹详情并渲染全步骤');
      expect(_activeLabels(tester), ['运行轨迹'],
          reason: '详情是列表的下钻，高亮仍落在「运行轨迹」');
      expect(tester.takeException(), isNull);
    });

    testWidgets('详情页返回回落到轨迹列表（单一出口，不裸 pop）', (tester) async {
      await _pumpTeacherHome(tester, repo: _FakeRunTraceRepo());
      await tester.tap(find.text('运行轨迹'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.textContaining('查询题库中的题目'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byWidgetPredicate(
        (w) => w is AppIconAction && w.semanticLabel == '返回',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_activeLabels(tester), ['运行轨迹']);
      expect(find.textContaining('查询题库中的题目'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    test('轨迹页经 HomeScreen 的单一 _go switch 打开（不散落 push / showDialog）',
        () {
      final src =
          File('lib/features/home/presentation/screens/home_screen.dart')
              .readAsStringSync();
      final inCode = src
          .split('\n')
          .where((l) =>
              l.contains('RunTracePage') && !l.trimLeft().startsWith('//'))
          .toList();
      expect(inCode, isNotEmpty,
          reason: '运行轨迹页必须经 HomeScreen 的 `_go` switch 打开（ADR-0059 单一导航状态）');
      for (final line in inCode) {
        expect(line.contains('Navigator'), isFalse,
            reason: '轨迹页不得用 Navigator.push / showDialog 绕开导航单源：$line');
      }
    });
  });
}

Widget _shell(Widget child, {RunTraceRepository? repo}) => ProviderScope(
      overrides: [
        if (repo != null) runTraceRepositoryProvider.overrideWithValue(repo),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(home: child),
      ),
    );

Future<void> _pumpList(
  WidgetTester tester, {
  required RunTraceRepository repo,
}) async {
  await tester.pumpWidget(
    _shell(AiRunTraceView(onOpenRun: (_) {}), repo: repo),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpDetail(
  WidgetTester tester,
  String runId, {
  RunTraceRepository? repo,
}) async {
  await tester.pumpWidget(
    _shell(AiRunTraceDetailView(runId: runId, onBack: () {}),
        repo: repo ?? _FakeRunTraceRepo()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// 侧栏里处于高亮态的标签（「我的」在底部用户区，不计入）。
List<String> _activeLabels(WidgetTester tester) => tester
    .widgetList<AppSidebarItem>(find.byType(AppSidebarItem))
    .where((item) => item.active)
    .map((item) => item.label)
    .toList();

UserModel _teacher() => UserModel(
      id: 'u1',
      username: 'teacher1',
      displayName: '妈妈',
      role: 'teacher',
    );

/// 桩掉 HomeScreen 初始化会拉的学生 / 班级数据（同
/// `teacher_nav_single_source_test` 的做法）：不桩的话教师端壳一挂上就往真实
/// 网络发请求，测试环境里只剩连接失败的噪音。
class _FakeStudentsRepo implements StudentsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<UserModel>> getStudents({
    String? classId,
    String? keyword,
  }) async =>
      const [];

  @override
  Future<Map<String, int>> getWrongQuestionCounts() async =>
      <String, int>{};
}

class _FakeClassesRepo implements ClassesRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();

  @override
  Future<List<ClassModel>> getClasses() async => const [];
}

/// 经 HomeScreen（真实导航单源）泵起教师端，桩掉运行轨迹取数。
Future<void> _pumpTeacherHome(
  WidgetTester tester, {
  required RunTraceRepository repo,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.init();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        studentsRepositoryProvider.overrideWithValue(_FakeStudentsRepo()),
        classesRepositoryProvider.overrideWithValue(_FakeClassesRepo()),
        runTraceRepositoryProvider.overrideWithValue(repo),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: HomeScreen(user: _teacher(), onLogout: () {}),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
