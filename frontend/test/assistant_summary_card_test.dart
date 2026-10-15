import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_clarify.dart';
import 'package:kids_learn/features/assistant/domain/assistant_summary.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_summary_card.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 「已确认规格」汇总卡（ADR-0095）：列出已填项 + 被默认填充的项，并可改。
///
/// 只做几何 / 行为断言（finders + 点击回调），**不装截图装置**——
/// `RenderRepaintBoundary.toImage()` 在无合成器的 widget 测试里永不完成。
void main() {
  Widget harness(AssistantSummaryCard card) => ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (_) => CupertinoApp(
          home: ShadToaster(
            child: SingleChildScrollView(child: card),
          ),
        ),
      );

  SummarySlot row({
    required String name,
    required String label,
    required String type,
    Object? value,
    String valueLabel = '',
    List<String> values = const <String>[],
  }) =>
      SummarySlot(
        slot: ClarifySlot(
          name: name,
          prompt: '请补充$label',
          type: type,
          values: values,
          min: type == 'int' ? 1 : null,
          max: type == 'int' ? 9 : null,
        ),
        label: label,
        value: value,
        valueLabel: valueLabel,
      );

  testWidgets('逐项列出已确认规格，默认值也念出来', (tester) async {
    await tester.pumpWidget(
      harness(
        AssistantSummaryCard(
          slots: <SummarySlot>[
            row(name: 'subject', label: '科目', type: 'enum', value: '数学', valueLabel: '数学'),
            row(name: 'qtype', label: '题型', type: 'enum', value: 'choice', valueLabel: '选择题'),
            row(name: 'knowledge_point', label: '知识点', type: 'string', valueLabel: '（未指定）'),
          ],
          onPrompt: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已确认规格：'), findsOneWidget);
    expect(find.text('科目'), findsOneWidget);
    expect(find.text('数学'), findsOneWidget);
    // 英文码必须念成中文，否则用户看不懂也就无从改起（US5）
    expect(find.text('选择题'), findsOneWidget);
    expect(find.text('choice'), findsNothing);
    // 被默认填充的项要显式标出来
    expect(find.text('（未指定）'), findsOneWidget);
  });

  testWidgets('点「修改」展开取值控件，选中的值经 onPrompt 发出', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      harness(
        AssistantSummaryCard(
          slots: <SummarySlot>[
            row(
              name: 'qtype',
              label: '题型',
              type: 'enum',
              value: 'choice',
              valueLabel: '选择题',
              values: const <String>['choice', 'fill', 'calc', 'open'],
            ),
          ],
          onPrompt: sent.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 未展开时没有取值 chips
    expect(find.text('填空题'), findsNothing);
    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();

    expect(find.text('填空题'), findsOneWidget);
    await tester.tap(find.text('填空题'));
    await tester.pumpAndSettle();
    expect(sent, ['fill']);
    // 改完收起，不留在展开态
    expect(find.text('填空题'), findsNothing);
  });

  testWidgets('bool 槽不给修改入口（后端按关键词抽取，「是/否」定位不到槽）',
      (tester) async {
    await tester.pumpWidget(
      harness(
        AssistantSummaryCard(
          slots: <SummarySlot>[
            row(name: 'multi', label: '多选', type: 'bool', value: false, valueLabel: '否'),
          ],
          onPrompt: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('多选'), findsOneWidget);
    expect(find.text('否'), findsOneWidget);
    expect(find.text('修改'), findsNothing);
  });
}
