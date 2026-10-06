// 定位「改了学期后知识点 options 不变」（ADR-0061 §L）。
//
// 现象：布置任务表单把学期从上学期切到下学期，知识落下拉的选项不变。
//
// 拆成两个可确定性验证的单元（不依赖整页 widget 树——裸 ShadApp 下表单不渲染，
// 那属于测试脚手架问题、与本 bug 无关）：
// 1. provider 层：family key 含学期 → 不同学期必须是**不同**的 provider 实例与数据；
// 2. 视图层：TaskSpecRowEditor 的 knowledgePointValues/Labels 随 options 变化。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/home/domain/repositories/material_repository.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/teacher_task_spec_row.dart';
import 'package:kids_learn/features/home/providers/home_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 按学期返回不同目录的桩仓库（模拟后端 ADR-0061 §J 的并集/精确语义）。
class _SemesterAwareRepo implements MaterialRepository {
  final List<String> calls = [];

  static const _table = {
    '上学期': ['上册A', '上册B', '上册C'],
    '下学期': ['下册X', '下册Y'],
  };

  @override
  Future<KnowledgePointDirectory> getKnowledgePointDirectory({
    required String subject,
    required int grade,
    String semester = '',
  }) async {
    calls.add('$subject/$grade/$semester');
    final names = semester.isEmpty
        ? const ['不限1', '不限2']
        : (_table[semester] ?? const <String>[]);
    return KnowledgePointDirectory(
      items: [
        for (final n in names)
          KnowledgePointOption(id: n, name: n, semester: semester),
      ],
      // 与后端一致：没有真实知识点时给说明（ADR-0061 §L）。
      notice: names.isEmpty && semester.isNotEmpty ? '该学期还没有资料知识点' : '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 正确的挂载方式（对齐 `model_management_ui_test.dart`）：`ShadApp.custom` +
/// `AppTheme.shadFor(...)`。裸 `MaterialApp` 下 ShadSelect 拿不到主题会抛——那是
/// 测试脚手架问题，不是被测行为。
Widget _wrap(WidgetTester tester, Widget child) {
  return ShadApp.custom(
    theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
    appBuilder: (context) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 900, height: 700, child: child),
      ),
    ),
  );
}

void main() {
  group('knowledgePointsProvider · 学期进key', () {
    test('不同学期 → 不同请求与不同数据（并集/精确两态）', () async {
      final repo = _SemesterAwareRepo();
      final container = ProviderContainer(
        overrides: [materialRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      // 不限学期 = 并集
      final all = await container.read(
        knowledgePointsProvider(('数学', 4, '')).future,
      );
      expect(all.items.map((e) => e.name), ['不限1', '不限2']);

      // 上学期
      final up = await container.read(
        knowledgePointsProvider(('数学', 4, '上学期')).future,
      );
      expect(up.items.map((e) => e.name), ['上册A', '上册B', '上册C']);

      // 下学期 = 与上学期**不同**的数据
      final down = await container.read(
        knowledgePointsProvider(('数学', 4, '下学期')).future,
      );
      expect(down.items.map((e) => e.name), ['下册X', '下册Y']);

      // 三个 key 各自发过一次请求（没有互相复用缓存）
      expect(repo.calls, [
        '数学/4/',
        '数学/4/上学期',
        '数学/4/下学期',
      ]);
    });

    test('记录字面量：family key 确实是三元组（含学期）', () {
      // 这条是「不许把学期从 key 里去掉」的守卫：三元组与二元组不兼容，
      // 一旦有人退回 (subject, grade)，下面按 key watch 的调用会在编译期报错。
      const key = ('数学', 4, '上学期');
      expect(key.$3, '上学期');
    });

    test('notice 透传：该学期没有真实知识点时要能说人话（ADR-0061 §L）', () async {
      // 桩仓库：某学期目录为空 → notice 非空
      final repo = _SemesterAwareRepo();
      final container = ProviderContainer(
        overrides: [materialRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final empty = await container.read(
        knowledgePointsProvider(('数学', 4, '空学期')).future,
      );
      expect(empty.items, isEmpty);
      expect(empty.notice, isNotEmpty, reason: '空目录必须给出说明而不是静默');

      // 有数据时 notice 为空（不制造噪声）
      final withData = await container.read(
        knowledgePointsProvider(('数学', 4, '上学期')).future,
      );
      expect(withData.notice, isEmpty);
    });
  });

  group('TaskSpecRowEditor · 选项随学期变化', () {
    Widget build({
      required List<KnowledgePointOption> options,
      required String semester,
      String current = '',
    }) {
      final ctrl = TextEditingController(text: current);
      final countCtrl = TextEditingController(text: '5');
      addTearDown(ctrl.dispose);
      addTearDown(countCtrl.dispose);
      return TaskSpecRowEditor(
        subject: '数学',
        onSubjectChanged: (_) {},
        knowledgePoint: ctrl,
        qtype: 'calc',
        onQtypeChanged: (_) {},
        count: countCtrl,
        grade: 4,
        onGradeChanged: (_) {},
        semester: semester,
        onSemesterChanged: (_) {},
        removable: false,
        index: 0,
        onRemove: () {},
        knowledgePointOptions: options,
      );
    }

    testWidgets('限定学期：选项就是该学期目录、无后缀', (tester) async {
      await tester.pumpWidget(
        _wrap(tester, build(
              options: const [
                KnowledgePointOption(id: 'a', name: '上册A', semester: '上学期'),
                KnowledgePointOption(id: 'b', name: '上册B', semester: '上学期'),
              ],
              semester: '上学期',
            )),
      );
      final editor =
          tester.widget<TaskSpecRowEditor>(find.byType(TaskSpecRowEditor));
      expect(editor.knowledgePointValues, ['上册A', '上册B']);
      expect(editor.knowledgePointLabels, ['上册A', '上册B']);
    });

    testWidgets('不限学期的跨学期并集：逐项标出自己的学期', (tester) async {
      await tester.pumpWidget(
        _wrap(tester, build(
              options: const [
                KnowledgePointOption(id: 'a', name: '上册A', semester: '上学期'),
                KnowledgePointOption(id: 'x', name: '下册X', semester: '下学期'),
              ],
              semester: '',
            )),
      );
      final editor =
          tester.widget<TaskSpecRowEditor>(find.byType(TaskSpecRowEditor));
      expect(editor.knowledgePointValues, ['上册A', '下册X']);
      // 不限 → 没有「当前学期」，每项都标自己的学期
      expect(editor.knowledgePointLabels, ['上册A（上学期）', '下册X（下学期）']);
    });

    testWidgets('当前文本不在目录里也不丢（补到首位）', (tester) async {
      await tester.pumpWidget(
        _wrap(tester, build(
              options: const [
                KnowledgePointOption(id: 'a', name: '上册A', semester: '上学期'),
              ],
              semester: '上学期',
              current: '两位数加减法',
            )),
      );
      final editor =
          tester.widget<TaskSpecRowEditor>(find.byType(TaskSpecRowEditor));
      expect(editor.knowledgePointValues.first, '两位数加减法');
      expect(editor.knowledgePointValues, contains('上册A'));
    });
  });
}
