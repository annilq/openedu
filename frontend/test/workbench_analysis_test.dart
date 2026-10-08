import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/analytics/domain/models/analytics_models.dart';
import 'package:kids_learn/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:kids_learn/features/analytics/providers/analytics_provider.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/features/students/providers/students_provider.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/workbench_analysis.dart';
import 'package:kids_learn/shared/domain/models/class_model.dart';
import 'package:kids_learn/shared/domain/models/student_import_result.dart';
import 'package:kids_learn/shared/domain/models/user.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/analytics_charts.dart';

/// 分析层测试（ticket 04，ADR-0075 §2.2）。
///
/// 关注点：非 Material 根树构建、三块图表渲染（堆叠 / 分组 / 横向）、孤儿「未知」
/// 警示条显式出现、作用域 / 维度切换不抛错（含切到「年级」时的口径标注与切到
/// 「单个班级」时显式班级选择器）。[AnalyticsNotifier] 同时消费 analytics / classes /
/// students 三仓，测试须三仓同覆。
class FakeAnalyticsRepository implements AnalyticsRepository {
  @override
  Future<WrongDistributionResp> getWrongDistribution({
    required String scope,
    String? classId,
    required String dimension,
  }) async =>
      WrongDistributionResp(
        scope: scope,
        dimension: dimension,
        totalActive: 30,
        totalGraduated: 10,
        total: 40,
        groups: [
          WrongDistributionGroup(
              group: '数学', active: 20, graduated: 6, total: 26),
          WrongDistributionGroup(
              group: '语文', active: 10, graduated: 4, total: 14),
        ],
        orphanCount: 3,
      );

  @override
  Future<AccuracyResp> getAccuracy({
    required String scope,
    String? classId,
    required String dimension,
  }) async =>
      AccuracyResp(
        scope: scope,
        dimension: dimension,
        source: scope,
        groups: [
          AccuracyGroup(
            group: '数学',
            practice: AccuracyBreakdown(total: 100, correct: 80, accuracy: 0.8),
            review: AccuracyBreakdown(total: 50, correct: 40, accuracy: 0.8),
            overall: AccuracyBreakdown(total: 150, correct: 120, accuracy: 0.8),
          ),
          AccuracyGroup(
            group: '语文',
            practice: AccuracyBreakdown(total: 80, correct: 50, accuracy: 0.625),
            review: AccuracyBreakdown(total: 40, correct: 30, accuracy: 0.75),
            overall: AccuracyBreakdown(total: 120, correct: 80, accuracy: 0.667),
          ),
        ],
        orphanCount: 0,
      );

  @override
  Future<MasteryResp> getMastery({
    required String scope,
    String? classId,
  }) async =>
      MasteryResp(
        scope: scope,
        totalKnowledgePoints: 10,
        masteredCount: 6,
        items: [
          MasteryGroup(
            knowledgePoint: '分数加减',
            subject: '数学',
            grade: 4,
            totalAnswers: 100,
            correctAnswers: 40,
            accuracy: 0.4,
            activeWrong: 12,
            maxReviewStage: 1,
            score: 40,
            level: '薄弱',
          ),
          MasteryGroup(
            knowledgePoint: '已掌握项',
            subject: '数学',
            grade: 4,
            totalAnswers: 90,
            correctAnswers: 85,
            accuracy: 0.94,
            activeWrong: 0,
            maxReviewStage: 3,
            score: 94,
            level: '熟练',
          ),
        ],
        orphanCount: 0,
      );
}

class FakeClassesRepository implements ClassesRepository {
  @override
  Future<List<ClassModel>> getClasses() async => [
        ClassModel(id: 'c1', name: '一班', grade: 4, studentCount: 8),
        ClassModel(id: 'c2', name: '二班', grade: 4, studentCount: 5),
      ];
}

class FakeStudentsRepository implements StudentsRepository {
  @override
  Future<UserModel> createChild({
    required String username,
    required String password,
    required String displayName,
    int? grade,
  }) async =>
      UserModel(
        id: 's',
        username: username,
        displayName: displayName,
        role: 'child',
        grade: grade,
      );

  @override
  Future<UserModel> updateChild({
    required String studentId,
    String? displayName,
    int? grade,
  }) async =>
      UserModel(
        id: studentId,
        username: studentId,
        displayName: displayName ?? '',
        role: 'child',
        grade: grade,
      );

  @override
  Future<List<UserModel>> getChildren() async => [];

  @override
  Future<List<UserModel>> getStudents({
    String? classId,
    String? keyword,
  }) async =>
      [];

  @override
  Future<Map<String, int>> getWrongQuestionCounts() async => {};

  @override
  Future<void> batchReassign({
    required String? classId,
    required List<String> studentIds,
  }) async {}

  @override
  Future<StudentImportResultModel> importStudents({
    required List<int> bytes,
    required String filename,
  }) async =>
      const StudentImportResultModel(created: 0, skipped: 0, errors: []);

  @override
  Future<Uint8List> downloadImportTemplate() async => Uint8List(0);
}

Widget _wrap(Widget child) => ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
      appBuilder: (context) => CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 720,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('分析层非 Material 树构建、三块图表渲染、孤儿未知警示条出现',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsRepositoryProvider
              .overrideWith((ref) => FakeAnalyticsRepository()),
          classesRepositoryProvider
              .overrideWith((ref) => FakeClassesRepository()),
          studentsRepositoryProvider
              .overrideWith((ref) => FakeStudentsRepository()),
        ],
        child: _wrap(const WorkbenchAnalysis()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: '非 Material 树中不得抛「No Material widget found」');

    expect(find.byType(AppStackedBarChart), findsOneWidget);
    expect(find.byType(AppGroupedBarChart), findsOneWidget);
    expect(find.byType(AppBarChart), findsOneWidget);
    expect(find.text('未知（原题已删除）3 道：孤儿错题，无法归入任何分组。'),
        findsOneWidget);
  });

  testWidgets('切换维度/作用域不抛错（年级标注 + 班级选择器显式出现）',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsRepositoryProvider
              .overrideWith((ref) => FakeAnalyticsRepository()),
          classesRepositoryProvider
              .overrideWith((ref) => FakeClassesRepository()),
          studentsRepositoryProvider
              .overrideWith((ref) => FakeStudentsRepository()),
        ],
        child: _wrap(const WorkbenchAnalysis()),
      ),
    );
    await tester.pumpAndSettle();

    // 默认维度为知识点，切到「年级」应显式展示口径标注。
    await tester.tap(find.text('年级'));
    await tester.pumpAndSettle();
    expect(
      find.text('年级按「题目」归类（即试卷所属年级），非学生当前所在年级。'),
      findsOneWidget,
    );

    // 切到「单个班级」作用域，应显式出现班级选择器。
    await tester.tap(find.text('单个班级'));
    await tester.pumpAndSettle();
    expect(find.text('选择班级'), findsAtLeastNWidgets(1));

    expect(tester.takeException(), isNull);
  });
}
