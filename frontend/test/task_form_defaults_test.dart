// 守住「发布任务表单默认值数据通路」纪律（2026-10-14）。
//
// 回归的 bug：表单曾用硬编码常量冒充默认值——学科恒「数学」、知识点恒「两位数加减法」、
// 题型恒 calc、年级恒兜底 2、标题恒「今日练习」、总题数恒 4，「+ 加学科」再凭空塞一行
// 「语文/字词积累」。教师只选派发班级就点生成，会得到一份来历不明的二年级数学卷。
// 现在的纪律：每个初始值都要有数据通路（班级→年级 / CTA→学科·知识点·年级 /
// 系统时钟→标题 / 学科→题型白名单首项），没有通路的一律留空、由生成前校验说人话。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/providers/assistant_provider.dart';
import 'package:kids_learn/features/home/domain/repositories/tasks_repository.dart';
import 'package:kids_learn/features/home/presentation/providers/task_form_prefill.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/task_form_defaults.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/task_spec_row_data.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/teacher_task_form_view.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/teacher_task_spec_row.dart';
import 'package:kids_learn/features/home/providers/home_provider.dart';
import 'package:kids_learn/features/model_management/domain/models.dart';
import 'package:kids_learn/features/model_management/domain/repositories/models_repository.dart';
import 'package:kids_learn/features/model_management/presentation/providers/models_notifier.dart';
import 'package:kids_learn/shared/features/materials/domain/repositories/material_repository.dart';
import 'package:kids_learn/shared/presentation/resource.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

class _StubTasksRepo implements TasksRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubAssistantRepo implements AssistantRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubModelsRepo implements ModelsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 种子模型列表：表单挂载即拉模型，桩仓库不接网络。
class _SeededModels extends ModelsNotifier {
  _SeededModels() : super(_StubModelsRepo()) {
    state = const ResourceLoaded<ModelsData>(ModelsData(ModelListResp(), []));
  }

  @override
  Future<void> load() async {}
}

/// 知识点目录桩：只回答表单会问的那一个方法，其余一律 UnimplementedError。
class _StubMaterialRepo implements MaterialRepository {
  @override
  Future<KnowledgePointDirectory> getKnowledgePointDirectory({
    required String subject,
    required int grade,
    String semester = '',
  }) async =>
      KnowledgePointDirectory(
        items: const [
          KnowledgePointOption(id: 'a', name: '目录知识点甲', semester: ''),
          KnowledgePointOption(id: 'b', name: '目录知识点乙', semester: ''),
        ],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 挂载真实表单（对齐 model_management_ui_test 的挂载方式）。
///
/// 表单用 AppToast 报校验错误，而 ShadApp.custom 不装 toaster——显式包一层
/// ShadToaster，否则「请先选择要布置的班级或学生」这类提示无法断言。
Future<void> pumpForm(
  WidgetTester tester, {
  TaskFormPrefill? prefill,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelsNotifierProvider.overrideWith((ref) => _SeededModels()),
        tasksRepositoryProvider.overrideWithValue(_StubTasksRepo()),
        assistantRepositoryProvider.overrideWithValue(_StubAssistantRepo()),
        materialRepositoryProvider.overrideWithValue(_StubMaterialRepo()),
        if (prefill != null)
          taskFormPrefillProvider.overrideWith((ref) => prefill),
      ],
      child: ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (context) => MaterialApp(
          home: ShadToaster(
            child: Scaffold(
              body: SizedBox(
                width: 900,
                height: 700,
                child: const TeacherTaskFormView(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('TaskSpecRow · 初始值', () {
    test('TaskSpecRow() 全空：没有数据通路的默认值一律留空', () {
      final row = TaskSpecRow();
      addTearDown(row.dispose);
      expect(row.subject, isNull);
      expect(row.qtype, isNull);
      expect(row.knowledgePoint.text, '');
      expect(row.count.text, '');
      expect(row.semester, '');
    });

    test('构造带学科 → 题型落该学科白名单首项（ADR-0055 §12）', () {
      expect(TaskSpecRow(subject: '数学').qtype, 'calc');
      expect(TaskSpecRow(subject: '语文').qtype, 'fill');
      expect(TaskSpecRow(subject: '英语').qtype, 'choice');
    });

    test('onSubjectChanged：题型不在新白名单 → 回落默认；仍在 → 保留', () {
      final outOfWhitelist = TaskSpecRow(subject: '数学');
      addTearDown(outOfWhitelist.dispose);
      outOfWhitelist.onSubjectChanged('英语');
      expect(outOfWhitelist.qtype, 'choice', reason: '英语没有计算题，calc 不能留');

      final stillValid = TaskSpecRow(subject: '数学');
      addTearDown(stillValid.dispose);
      stillValid.qtype = 'choice';
      stillValid.onSubjectChanged('语文');
      expect(stillValid.qtype, 'choice', reason: 'choice 在语文白名单里，不该被换掉');

      final unset = TaskSpecRow();
      addTearDown(unset.dispose);
      unset.onSubjectChanged('数学');
      expect(unset.qtype, 'calc', reason: '未选题型的行切学科时直接派生默认');
    });
  });

  group('TaskSpecRow.toSpec', () {
    test('行就绪 → 规格带继承年级；手动年级覆盖继承', () {
      final row = TaskSpecRow(subject: '数学', knowledgePoint: 'KP', count: '3');
      addTearDown(row.dispose);
      final inherited = row.toSpec(3)!;
      expect(inherited.grade, 3);
      expect(inherited.count, 3);
      expect(inherited.qtype, 'calc');
      expect(inherited.knowledgePoint, 'KP');
      expect(inherited.subject, '数学');

      row.grade = 5;
      expect(row.toSpec(3)!.grade, 5, reason: '手动指定的年级压过继承值');
    });

    test('任一未定 → null（null 规格不会流进请求）', () {
      expect(TaskSpecRow(knowledgePoint: 'KP', count: '3').toSpec(3), isNull,
          reason: '学科未选');
      expect(TaskSpecRow(subject: '数学', count: '3').toSpec(3), isNull,
          reason: '知识点未填');
      expect(TaskSpecRow(subject: '数学', knowledgePoint: 'KP').toSpec(3), isNull,
          reason: '题数未填');
      expect(
          TaskSpecRow(subject: '数学', knowledgePoint: 'KP', count: '0').toSpec(3),
          isNull,
          reason: '题数为 0');
      expect(
          TaskSpecRow(subject: '数学', knowledgePoint: 'KP', count: '3').toSpec(null),
          isNull,
          reason: '年级未定：没选派发班级也没手动选');
    });
  });

  group('specRowError', () {
    test('逐项缺失的人话提示，与 toSpec 同一套未定判据', () {
      expect(specRowError(TaskSpecRow()), '请选择学科');

      final noKnowledgePoint = TaskSpecRow(subject: '数学');
      addTearDown(noKnowledgePoint.dispose);
      expect(specRowError(noKnowledgePoint), '请选择知识点');

      final noGrade =
          TaskSpecRow(subject: '数学', knowledgePoint: 'KP');
      addTearDown(noGrade.dispose);
      expect(specRowError(noGrade), '请选择年级');
      expect(specRowError(noGrade, inheritedGrade: 3), '每行题数至少为 1');

      final ready = TaskSpecRow(subject: '数学', knowledgePoint: 'KP', count: '2');
      addTearDown(ready.dispose);
      expect(specRowError(ready, inheritedGrade: 3), isNull);
    });
  });

  group('defaultTaskTitle', () {
    test('按传入日期生成，不是冻结的「今日练习」', () {
      expect(defaultTaskTitle(DateTime(2026, 10, 14)), '10月14日练习');
      expect(defaultTaskTitle(DateTime(2027, 1, 2)), '1月2日练习');
    });
  });

  group('TaskFormPrefill', () {
    test('学科/年级可选：缺省落入表单生成前校验', () {
      const prefill = TaskFormPrefill(knowledgePoint: 'KP');
      expect(prefill.subject, isNull);
      expect(prefill.grade, isNull);
    });
  });

  group('表单挂载 · widget 层', () {
    testWidgets('新表单：初始行全空，没有一处来历不明的默认值', (tester) async {
      await pumpForm(tester);

      expect(find.byType(TaskSpecRowEditor), findsOneWidget);
      expect(find.text('请选择学科'), findsOneWidget);
      expect(find.text('两位数加减法'), findsNothing);
      expect(find.text('今日练习'), findsNothing);
      expect(find.text('字词积累'), findsNothing);
      final now = DateTime.now();
      expect(find.text('${now.month}月${now.day}日练习'), findsOneWidget,
          reason: '标题默认值的数据通路是系统时钟（挂载当天的日期）');
    });

    testWidgets('什么都没选就点生成：先拦派发目标', (tester) async {
      await pumpForm(tester);
      await tester.ensureVisible(find.text('生成任务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成任务'));
      await tester.pumpAndSettle();
      expect(find.text('请先选择要布置的班级或学生'), findsOneWidget);
    });

    testWidgets('「+ 加学科」加的是空行，不再凭空塞「语文/字词积累」', (tester) async {
      await pumpForm(tester);
      await tester.tap(find.text('+ 加学科'));
      await tester.pumpAndSettle();
      expect(find.text('请选择学科'), findsNWidgets(2));
      expect(find.text('字词积累'), findsNothing);
    });

    testWidgets('CTA 预填：学科/知识点有数据通路，落进首行', (tester) async {
      await pumpForm(
        tester,
        prefill: const TaskFormPrefill(
          subject: '语文',
          knowledgePoint: '字词',
          grade: 3,
        ),
      );
      expect(find.text('语文'), findsOneWidget,
          reason: '学科经 onSubjectChanged 落入，题型随白名单派生');
      expect(find.text('字词'), findsOneWidget,
          reason: '预填知识点即使不在目录里也保留为首选项');
    });
  });
}
