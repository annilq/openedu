// 守住「草稿审核」页任务信息卡的排版契约。
//
// 背景：统计行（题目数 / 已入题库）与出题规格 chips 原先塞在同一个 `Wrap` 里，
// 规格块还被压了「可用宽度 × 0.45」的上限。结果是学科一多，chips 就在统计行右侧
// 折成第二行、左对齐线断裂（820 宽实测：统计行高 20，整体行高被撑到 64），
// 0.45 这个补丁也只是把溢出往后推。现在拆成两块：统计行一行读数、规格块独占
// 一行通栏 chip 流。`flutter analyze` 照不出这类问题（不是类型错误），只能守行为。
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

/// 本测试只渲染初始状态，任何仓库方法都不该被调用。
class _StubReview implements TaskReviewRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubAssistant implements AssistantRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 四个学科规格：正是把旧排版撑坏的最小规模。
TaskModel _taskWithSpecs() => TaskModel(
      id: 't1',
      title: '三年级混合练习',
      status: 'draft',
      questions: [
        for (var i = 0; i < 4; i++)
          QuestionModel(
            id: 'tq$i',
            questionId: i < 2 ? 'q$i' : null,
            subject: '数学',
            grade: 3,
            stem: '第 ${i + 1} 题',
            qtype: 'single_choice',
            knowledgePoint: '两位数乘法',
          ),
      ],
      specs: [
        TaskSpecModel(
            subject: '数学',
            grade: 3,
            knowledgePoint: '两位数乘法',
            qtype: 'single_choice',
            count: 3),
        TaskSpecModel(
            subject: '语文',
            grade: 3,
            knowledgePoint: '古诗默写',
            qtype: 'fill_blank',
            count: 2),
        TaskSpecModel(
            subject: '英语',
            grade: 3,
            knowledgePoint: '一般现在时',
            qtype: 'single_choice',
            count: 2),
        TaskSpecModel(
            subject: '数学',
            grade: 3,
            knowledgePoint: '分数初步认识',
            qtype: 'fill_blank',
            count: 2),
      ],
    );

void main() {
  Future<void> pumpPage(WidgetTester tester, Size size) async {
    // 必须显式设视口：test surface 默认 800×600，`SizedBox(width: ...)` 会被静默裁掉。
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskReviewRepositoryProvider.overrideWithValue(_StubReview()),
          assistantRepositoryProvider.overrideWithValue(_StubAssistant()),
        ],
        child: ShadApp.custom(
          // 断言几何必须传真实主题：不传会走 shadcn 默认主题（内边距/高度都不同）。
          theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            home: ParentTaskReviewScreen(
              task: _taskWithSpecs(),
              onBackToHome: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('出题规格独占一行，不与统计行混排', (tester) async {
    await pumpPage(tester, const Size(820, 1000));

    // 统计行：两个 _Stat（RichText 里的标签）。
    final statsBottom =
        tester.getRect(find.textContaining('已入题库', findRichText: true).first).bottom;
    final specsLabel = tester.getRect(find.text('出题规格'));
    // 用完整 chip 文本匹配：题干/知识点里也有「两位数乘法」，textContaining 会误命中题卡。
    final firstChip = tester.getRect(find.text('数学·3·两位数乘法 x3'));

    // 规格块整体在统计行之下（拆块前这里是并排的，chips 顶与统计行同高）。
    expect(specsLabel.top, greaterThan(statsBottom));
    expect(firstChip.top, greaterThan(specsLabel.bottom));

    // 第一个 chip 的左缘 == 规格块左缘：chip 流从块左缘起排，不再被推到
    // 统计行右侧（旧版首 chip 左缘 = 统计行右缘 + xl2）。
    final statsLeft =
        tester.getRect(find.textContaining('题目数', findRichText: true).first).left;
    // 规格块图标与统计行同缩进：统计文本左缘 - 自身图标(18) - 间距(8) = 块左缘。
    expect(
      tester.getRect(find.byIcon(LucideIcons.listChecks)).left,
      closeTo(statsLeft - 26, 0.5),
    );
  });

  testWidgets('多学科 chip 通栏换行且不溢出卡片', (tester) async {
    await pumpPage(tester, const Size(820, 1000));

    final card = tester.getRect(find.byType(AppCard).first);
    const chipTexts = [
      '数学·3·两位数乘法 x3',
      '语文·3·古诗默写 x2',
      '英语·3·一般现在时 x2',
      '数学·3·分数初步认识 x2',
    ];
    for (final t in chipTexts) {
      final r = tester.getRect(find.text(t));
      // 通栏：chip 右缘仍在卡片内（带内边距），旧版 0.45 上限把 4 个 chip 压成两行。
      expect(r.right, lessThan(card.right - AppSpacing.lg));
      expect(r.left, greaterThan(card.left));
    }

    // 通栏 chip 流的契约：全部 chip 在「出题规格」标签之下、卡片内容区内，
    // 且每一行的行首 chip 都从块左缘起排（左侧没有统计行挡路）。
    // 不断言「同一行」：守卫不加载真字体，测宽与真机略有出入，行数会漂。
    final labelBottom = tester.getRect(find.text('出题规格')).bottom;
    final blockLeft = tester.getRect(find.text(chipTexts.first)).left;
    final lefts = [
      for (final t in chipTexts) tester.getRect(find.text(t)).left,
    ];
    expect(lefts.reduce((a, b) => a < b ? a : b), blockLeft);
    for (final t in chipTexts) {
      final r = tester.getRect(find.text(t));
      expect(r.top, greaterThan(labelBottom));
      expect(r.right, lessThan(card.right - AppSpacing.lg));
      expect(r.left, greaterThanOrEqualTo(blockLeft));
    }
  });
}
