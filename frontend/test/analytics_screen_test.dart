// 守住一条已从崩溃里学到的约束：App 根是 ShadApp/CupertinoApp，**整棵 widget 树
// 没有 Material 祖先**。任何 Material 系控件放进统计页都会在构建期抛
// 「No Material widget found」——不是某个按钮失灵，而是整页红屏。
//
// `flutter analyze` 完全照不出来，只有这种「在不装 Material 的树里真的构建一次」
// 的测试能拦住它。同时覆盖 ticket 12 的关键口径：孤儿错题标注「未知」、年级维度
// 提示「题目年级」、作用域三态切换受控。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/analytics/domain/models/analytics_models.dart';
import 'package:kids_learn/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:kids_learn/features/analytics/providers/analytics_provider.dart';
import 'package:kids_learn/features/analytics/presentation/screens/analytics_screen.dart';
import 'package:kids_learn/shared/domain/models/class_model.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/shared/domain/models/student_import_result.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import 'package:kids_learn/features/students/providers/students_provider.dart';
import 'package:kids_learn/shared/domain/models/user.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

// 固定的三份聚合：错题带 2 条孤儿，正确率/掌握度无孤儿，便于断言「未知」只出现一次。
const _wrong = WrongDistributionResp(
  scope: 'all',
  dimension: 'knowledge_point',
  totalActive: 3,
  totalGraduated: 1,
  total: 4,
  groups: [
    WrongDistributionGroup(group: '分数加减', active: 3, graduated: 1, total: 4),
  ],
  orphanCount: 2,
);

const _accuracy = AccuracyResp(
  scope: 'all',
  dimension: 'knowledge_point',
  source: 'all',
  groups: [
    AccuracyGroup(
      group: '分数加减',
      practice: AccuracyBreakdown(total: 10, correct: 8, accuracy: 0.8),
      review: AccuracyBreakdown(total: 5, correct: 4, accuracy: 0.8),
      overall: AccuracyBreakdown(total: 15, correct: 12, accuracy: 0.8),
    ),
  ],
  orphanCount: 0,
);

const _mastery = MasteryResp(
  scope: 'all',
  totalKnowledgePoints: 1,
  masteredCount: 0,
  items: [
    MasteryGroup(
      knowledgePoint: '分数加减',
      subject: 'math',
      grade: 4,
      totalAnswers: 15,
      correctAnswers: 12,
      accuracy: 0.8,
      activeWrong: 2,
      maxReviewStage: 1,
      score: 75.0,
      level: '入门',
    ),
  ],
  orphanCount: 0,
);

class _FakeAnalyticsRepository implements AnalyticsRepository {
  @override
  Future<WrongDistributionResp> getWrongDistribution({
    required String scope,
    String? studentId,
    String? classId,
    required String dimension,
  }) async =>
      _wrong;

  @override
  Future<AccuracyResp> getAccuracy({
    required String scope,
    String? studentId,
    String? classId,
    required String dimension,
  }) async =>
      _accuracy;

  @override
  Future<MasteryResp> getMastery({
    required String scope,
    String? studentId,
    String? classId,
  }) async =>
      _mastery;
}

class _FakeClassesRepository implements ClassesRepository {
  @override
  Future<List<ClassModel>> getClasses() async => const [
        ClassModel(id: 'c1', name: '一班', grade: 4, studentCount: 20),
        ClassModel(id: 'c2', name: '二班', grade: 4, studentCount: 18),
      ];
}

class _FakeStudentsRepository implements StudentsRepository {
  @override
  Future<List<UserModel>> getStudents({
    String? classId,
    String? keyword,
  }) async => [
        UserModel(
          id: 's1',
          username: 'xiaoming',
          displayName: '小明',
          role: 'child',
        ),
        UserModel(
          id: 's2',
          username: 'xiaohong',
          displayName: '小红',
          role: 'child',
        ),
      ];

  @override
  Future<UserModel> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
  }) async =>
      throw UnimplementedError();

  @override
  Future<UserModel> updateChild({
    required String studentId,
    String? displayName,
    int? grade,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<UserModel>> getChildren() async => throw UnimplementedError();

  @override
  Future<Map<String, int>> getWrongQuestionCounts() async =>
      throw UnimplementedError();

  @override
  Future<void> batchReassign({
    required String? classId,
    required List<String> studentIds,
  }) async =>
      throw UnimplementedError();

  @override
  Future<StudentImportResultModel> importStudents({
    required List<int> bytes,
    required String filename,
  }) async =>
      StudentImportResultModel(created: 0, skipped: 0, errors: const []);
}

Future<void> _pumpScreen(WidgetTester tester) async {
  // 默认测试视口只有 ~600px 高，会截断 AnalyticsScreen 内置的惰性 ListView，
  // 导致第三张卡片（掌握度）来不及构建。拉高到足以容纳三张卡片的高度。
  await tester.binding.setSurfaceSize(const Size(1200, 3000));
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        analyticsRepositoryProvider
            .overrideWithValue(_FakeAnalyticsRepository()),
        classesRepositoryProvider.overrideWithValue(_FakeClassesRepository()),
        studentsRepositoryProvider.overrideWithValue(_FakeStudentsRepository()),
      ],
      // 刻意**不**套 Material：真实的 App 根就是 ShadApp + CupertinoApp。
      child: ShadApp.custom(
        theme: AppTheme.shadFor(
            false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => CupertinoApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 900,
                height: 4000,
                child: const AnalyticsScreen(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // init() 在 addPostFrameCallback 触发，首次三份聚合为 Future.wait 异步。
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('无 Material 祖先下能构建，且三张卡片与孤儿标注都出现',
      (tester) async {
    await _pumpScreen(tester);

    // 构建没抛异常就是这条用例的主要断言。
    expect(tester.takeException(), isNull);

    // 三张聚合卡片标题都在。
    expect(find.text('学情统计'), findsOneWidget);
    expect(find.text('错题分布'), findsOneWidget);
    expect(find.text('正确率'), findsOneWidget);
    expect(find.text('掌握度'), findsOneWidget);

    // 孤儿错题（仅 wrong 带 2 条）以「未知」分组显式标注，且不混入有效分组。
    expect(find.text('未知（原题已删除）'), findsOneWidget);

    // 默认维度是知识点，年级提示不应出现。
    expect(find.textContaining('年级按'), findsNothing);
  });

  testWidgets('切到「年级」维度展示题目年级提示', (tester) async {
    await _pumpScreen(tester);

    expect(find.textContaining('年级按'), findsNothing);
    await tester.tap(find.text('年级'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text(
        '年级按「题目」归类（即试卷所属年级），非学生当前所在年级。',
      ),
      findsOneWidget,
    );
  });

  testWidgets('切到「单个班级」作用域展开班级选择器', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('选择班级'), findsNothing);
    await tester.tap(find.text('单个班级'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 切到「单个班级」作用域后，班级选择器展开（label 与 placeholder 同为
    // 「选择班级」→ 至少一条）。选项列表仅在打开下拉浮层时才会渲染，这里只验证
    // 选择器已出现，作用域切换受控。
    expect(find.text('选择班级'), findsAtLeastNWidgets(1));
  });
}
