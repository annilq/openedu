import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/analytics/domain/models/analytics_models.dart';
import 'package:kids_learn/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:kids_learn/features/analytics/presentation/providers/analytics_summary_provider.dart';
import 'package:kids_learn/features/analytics/providers/analytics_provider.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/workbench_glance.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/analytics_charts.dart';

/// 速览层测试（ticket 03，ADR-0075 §2.2）。
///
/// 关注点：非 Material 根树构建、四块图表渲染、孤儿「未知」警示条显式出现、
/// 薄弱知识点点击触发钻取回调。
class FakeAnalyticsRepository implements AnalyticsRepository {
  @override
  Future<WrongDistributionResp> getWrongDistribution({
    required String scope,
    String? classId,
    required String dimension,
  }) async =>
      WrongDistributionResp(
        scope: 'all',
        dimension: 'subject',
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
        scope: 'all',
        dimension: 'subject',
        source: 'all',
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
        scope: 'all',
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
            knowledgePoint: '阅读理解',
            subject: '语文',
            grade: 4,
            totalAnswers: 80,
            correctAnswers: 56,
            accuracy: 0.7,
            activeWrong: 6,
            maxReviewStage: 2,
            score: 70,
            level: '待巩固',
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
  testWidgets('速览层非 Material 树构建、四块图表渲染、孤儿未知警示条出现',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsRepositoryProvider
              .overrideWith((ref) => FakeAnalyticsRepository()),
        ],
        child: _wrap(const WorkbenchGlance()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: '非 Material 树中不得抛「No Material widget found」');

    expect(find.byType(AppDonutChart), findsOneWidget);
    expect(find.byType(AppGroupedBarChart), findsOneWidget);
    expect(find.byType(AppStackedBarChart), findsOneWidget);
    expect(find.text('未知（原题已删除）3 道：孤儿错题，无法归入任何分组。'),
        findsOneWidget);
  });

  testWidgets('薄弱知识点点击触发钻取回调（不混入有效分组）', (tester) async {
    String? drilled;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsRepositoryProvider
              .overrideWith((ref) => FakeAnalyticsRepository()),
        ],
        child: _wrap(WorkbenchGlance(
          onDrill: (kp) => drilled = kp,
        )),
      ),
    );
    await tester.pumpAndSettle();
    // 薄弱知识点按 activeWrong 降序，首项为「分数加减」（activeWrong=12）。
    await tester.tap(find.text('分数加减'));
    await tester.pump();
    expect(drilled, '分数加减');
  });
}
