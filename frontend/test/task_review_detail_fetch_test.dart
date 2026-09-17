// 守住「草稿审核」页的取数契约：进页面必须自己回后端取一次完整任务。
//
// 背景（ADR-0053 引入的回归）：列表接口 `GET /tasks` 改成只回摘要——`question_count`
// 加学科，**不再内嵌题目**。列表卡片改用 `displayQuestionCount` 显示题数（数字仍准），
// 但点卡片时传下去的这份 `TaskModel` 的 `questions` 恒为空。审核页当时直接拿它当
// initial state、从不调用 `load()`，于是家长看到的是「卡片写 3 题 / 详情说草稿暂未包含
// 任何题目（题目数 0）」——题一直在 `task_question` 表里，列表题数也是每次现算的，
// 只是没人去取。`flutter analyze` 照不出这类断链（类型全对），只能守行为。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:kids_learn/features/assistant/providers/assistant_provider.dart';
import 'package:kids_learn/features/home/domain/repositories/task_review_repository.dart';
import 'package:kids_learn/features/home/presentation/screens/parent_task_review_screen.dart';
import 'package:kids_learn/features/home/providers/home_provider.dart';
import 'package:kids_learn/shared/domain/models/models.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 记录取数请求的桩：`load` 是唯一应该被调用的仓库方法。
class _RecordingReview implements TaskReviewRepository {
  _RecordingReview(this.full);

  /// 服务端在这个 id 上真正持有的任务（含题目）。
  final TaskModel full;
  final List<String> loadCalls = [];

  @override
  Future<TaskModel> load(String taskId) async {
    loadCalls.add(taskId);
    return full;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubAssistant implements AssistantRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 列表接口给的那一份：`question_count` = 3，但**不含题目**（ADR-0053）。
TaskModel _summary(String id) => TaskModel(
      id: id,
      title: '三年级混合练习',
      status: 'draft',
      questions: const [],
      questionCount: 3,
      subjects: const ['数学'],
    );

/// 详情接口（`GET /tasks/{id}`）给的那一份：3 道题。
TaskModel _detail(String id) => TaskModel(
      id: id,
      title: '三年级混合练习',
      status: 'draft',
      questions: [
        for (var i = 0; i < 3; i++)
          QuestionModel(
            id: '$id-tq$i',
            subject: '数学',
            grade: 3,
            stem: '第 ${i + 1} 题',
            qtype: 'single_choice',
            knowledgePoint: '两位数乘法',
          ),
      ],
    );

void main() {
  Future<_RecordingReview> pump(
    WidgetTester tester,
    TaskModel summary,
    TaskModel detail,
  ) async {
    final repo = _RecordingReview(detail);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskReviewRepositoryProvider.overrideWithValue(repo),
          assistantRepositoryProvider.overrideWithValue(_StubAssistant()),
        ],
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            home: ParentTaskReviewScreen(
              task: summary,
              onBackToHome: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('从列表摘要点进来，页面补取详情并渲染出题目', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = await pump(tester, _summary('t1'), _detail('t1'));

    // 取数发生在这条任务的 id 上。
    expect(repo.loadCalls, ['t1']);

    // 症状本身：修复前这里是「草稿暂未包含任何题目」（questions 恒为空）。
    expect(find.text('草稿暂未包含任何题目'), findsNothing);

    // 题目真的画出来了——三张题卡，题干来自服务端那一份。
    for (var i = 1; i <= 3; i++) {
      expect(find.text('第 $i 题'), findsOneWidget);
    }
  });

  testWidgets('换成另一条任务会重新取数（不是沿用上一条的状态）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _RecordingReview(_detail('t2'));
    final overrides = [
      taskReviewRepositoryProvider.overrideWithValue(repo),
      assistantRepositoryProvider.overrideWithValue(_StubAssistant()),
    ];

    Widget app(TaskModel task) => ProviderScope(
          overrides: overrides,
          child: ShadApp.custom(
            theme:
                AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
            appBuilder: (context) => CupertinoApp(
              home: ParentTaskReviewScreen(
                task: task,
                onBackToHome: () {},
              ),
            ),
          ),
        );

    // 同一位置换成另一条任务：provider 以 taskId 为 key，新 key 是一个停在
    // 加载态的新 notifier —— 不在 didUpdateWidget 里补取数就会永远转圈。
    await tester.pumpWidget(app(_summary('t1')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(_summary('t2')));
    await tester.pumpAndSettle();

    expect(repo.loadCalls, ['t1', 't2']);
    expect(find.text('第 1 题'), findsOneWidget);
  });
}
