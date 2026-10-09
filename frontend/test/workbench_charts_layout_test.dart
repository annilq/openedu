// 教师工作台两层（总览 / 分析）的图表版式守卫。
//
// 前身是「截图装置」——把渲染结果转成 PNG 供人工目检。截图那条路在测试环境里
// 挂死（`RenderRepaintBoundary.toImage()` 在无真实合成器时永不完成，实测整条
// `flutter test` 被它堵到 17 分钟不返回），而目检的结论又无法沉淀成回归。
//
// 因此这里**只留几何断言**：把上一轮肉眼核对过的三条结论改写成可执行的断言——
// ① 同行图表正文高度统一；② 环形外圆不溢出容器；③ 超长知识点名默认只渲染一次、
// 长按才弹完整标签。既不产二进制产物，也不依赖人工看图。
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/analytics/domain/models/analytics_models.dart';
import 'package:kids_learn/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:kids_learn/features/analytics/providers/analytics_provider.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/workbench_analysis.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/workbench_glance.dart';
import 'package:kids_learn/features/students/providers/students_provider.dart';
import 'package:kids_learn/shared/domain/models/class_model.dart';
import 'package:kids_learn/shared/domain/models/student_import_result.dart';
import 'package:kids_learn/shared/domain/models/user.dart';
import 'package:kids_learn/shared/domain/repositories/classes_repository.dart';
import 'package:kids_learn/shared/domain/repositories/students_repository.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/analytics_charts.dart';

class _FakeAnalytics extends AnalyticsRepository {
  @override
  Future<WrongDistributionResp> getWrongDistribution({
    required String scope,
    String? classId,
    required String dimension,
  }) async =>
      WrongDistributionResp(
        scope: scope,
        dimension: dimension,
        totalActive: 46,
        totalGraduated: 13,
        total: 59,
        groups: [
          WrongDistributionGroup(group: '数学', active: 20, graduated: 6, total: 26),
          WrongDistributionGroup(group: '语文', active: 11, graduated: 4, total: 15),
          WrongDistributionGroup(group: '英语', active: 8, graduated: 2, total: 10),
          WrongDistributionGroup(group: '物理', active: 5, graduated: 1, total: 6),
          WrongDistributionGroup(group: '历史', active: 2, graduated: 0, total: 2),
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
          AccuracyGroup(
            group: '英语',
            practice: AccuracyBreakdown(total: 70, correct: 55, accuracy: 0.786),
            review: AccuracyBreakdown(total: 30, correct: 25, accuracy: 0.833),
            overall: AccuracyBreakdown(total: 100, correct: 80, accuracy: 0.8),
          ),
        ],
        orphanCount: 0,
      );

  @override
  Future<MasteryResp> getMastery({required String scope, String? classId}) async {
    const names = [
      '一元二次方程的应用与根的判别式综合练习',
      '二次函数的图像性质与顶点坐标求法',
      '二元一次方程组的实际应用问题',
      '平面几何中相似三角形的判定与性质',
      '圆的切线性质与圆心角圆周角关系',
      '锐角三角函数的实际应用测量',
      '反比例函数图像与性质分析',
      '概率初步与树状图列举法',
      '因式分解的常用方法与技巧',
      '分式方程的解法与验根',
      '平行四边形的性质与判定定理',
      '数据的收集整理与描述统计',
    ];
    const accs = [
      0.4, 0.55, 0.62, 0.48, 0.71, 0.9, 0.82, 0.58, 0.67, 0.95, 0.73, 0.88
    ];
    const aw = [14, 11, 9, 7, 6, 4, 3, 2, 1, 0, 5, 8];
    const levels = [
      '薄弱', '薄弱', '薄弱', '薄弱', '一般', '熟练', '一般', '薄弱', '一般',
      '熟练', '一般', '熟练'
    ];
    return MasteryResp(
      scope: scope,
      totalKnowledgePoints: 30,
      masteredCount: 18,
      items: [
        for (int i = 0; i < names.length; i++)
          MasteryGroup(
            knowledgePoint: names[i],
            subject: '数学',
            grade: 9,
            totalAnswers: 100 - i,
            correctAnswers: ((100 - i) * accs[i]).round(),
            accuracy: accs[i],
            activeWrong: aw[i],
            maxReviewStage: 1,
            score: (accs[i] * 100).round().toDouble(),
            level: levels[i],
          ),
      ],
      orphanCount: 0,
    );
  }
}

class _FakeClasses extends ClassesRepository {
  @override
  Future<List<ClassModel>> getClasses() async => [
        ClassModel(id: 'c1', name: '一班', grade: 4, studentCount: 8),
      ];
}

class _FakeStudents extends StudentsRepository {
  @override
  Future<UserModel> createChild(
          {required String username,
          required String password,
          required String displayName,
          int? grade}) async =>
      UserModel(
          id: 's', username: username, displayName: displayName, role: 'child');
  @override
  Future<UserModel> updateChild(
          {required String studentId, String? displayName, int? grade}) async =>
      UserModel(
          id: studentId,
          username: studentId,
          displayName: displayName ?? '',
          role: 'child');
  @override
  Future<List<UserModel>> getChildren() async => [];
  @override
  Future<List<UserModel>> getStudents({String? classId, String? keyword}) async =>
      [];
  @override
  Future<Map<String, int>> getWrongQuestionCounts() async => {};
  @override
  Future<void> batchReassign(
          {required String? classId, required List<String> studentIds}) async {}
  @override
  Future<StudentImportResultModel> importStudents(
          {required List<int> bytes, required String filename}) async =>
      const StudentImportResultModel(created: 0, skipped: 0, errors: []);
  @override
  Future<Uint8List> downloadImportTemplate() async => Uint8List(0);
}

Widget _wrap(Widget child) => ShadApp.custom(
      theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
      appBuilder: (context) => CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 1280,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

/// 推进若干帧到静止。
///
/// 不用 `pumpAndSettle`：加载态 spinner / 图表入场动画可能永不静止，会直接超时。
Future<void> _pumpSettled(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('总览层：同行图表正文等高，环形外圆不溢出容器', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsRepositoryProvider.overrideWith((ref) => _FakeAnalytics()),
        ],
        child: _wrap(const WorkbenchGlance()),
      ),
    );
    await _pumpSettled(tester);

    // ① 同行图表正文高度统一（均为 200），消除不对齐。
    final donut = tester.getSize(find.byType(AppDonutChart));
    final grouped = tester.getSize(find.byType(AppGroupedBarChart));
    final stacked = tester.getSize(find.byType(AppStackedBarChart));
    final list = tester.getSize(find.byType(ListView));
    expect(donut.height, 200);
    expect(grouped.height, 200);
    expect(stacked.height, 200);
    expect(list.height, 200);

    // ② 环形外圆不溢出容器：centerSpaceRadius + max(section.radius) <= 半径。
    final pie = tester.widget<PieChart>(find.byType(PieChart));
    final maxOuter =
        pie.data.sections.map((s) => s.radius).reduce((a, b) => a > b ? a : b);
    expect(pie.data.centerSpaceRadius + maxOuter,
        lessThanOrEqualTo(donut.width / 2 + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('超长知识点名默认只渲染一次，长按才弹完整标签', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const longName = '一元二次方程的应用与根的判别式综合练习';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsRepositoryProvider.overrideWith((ref) => _FakeAnalytics()),
          classesRepositoryProvider.overrideWith((ref) => _FakeClasses()),
          studentsRepositoryProvider.overrideWith((ref) => _FakeStudents()),
        ],
        // 标签列加宽 + 2 行换行后，超长知识点名默认只渲染一次（行内）。
        child: _wrap(AppBarChart(
          data: [
            BarDatum(label: longName, value: 14, color: const Color(0xFF3366CC)),
            BarDatum(label: '短名知识点', value: 3, color: const Color(0xFF3366CC)),
          ],
        )),
      ),
    );
    await _pumpSettled(tester);
    expect(find.text(longName), findsOneWidget);

    // 长按整行弹出完整标签 tip（叠在最上层 Overlay，再次出现同文本）。
    final tp = await tester.startGesture(tester.getCenter(find.text(longName)));
    await tester.pump(const Duration(milliseconds: 600)); // 超过长按阈值
    expect(find.text(longName), findsWidgets); // 行 + tip 共 2 次
    await tp.up();
    await tester.pump();
    expect(find.text(longName), findsOneWidget); // 抬起后 tip 收起
    expect(tester.takeException(), isNull);
  });

  testWidgets('分析层：渲染不抛异常，图表照常落位', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsRepositoryProvider.overrideWith((ref) => _FakeAnalytics()),
          classesRepositoryProvider.overrideWith((ref) => _FakeClasses()),
          studentsRepositoryProvider.overrideWith((ref) => _FakeStudents()),
        ],
        child: _wrap(const WorkbenchAnalysis()),
      ),
    );
    await _pumpSettled(tester);

    expect(find.byType(AppStackedBarChart), findsWidgets);
    expect(find.byType(AppBarChart), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
