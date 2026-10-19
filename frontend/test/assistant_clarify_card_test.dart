import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_clarify.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_clarify_card.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 缺槽引导卡（ADR-0095 / ADR-0100）。
///
/// 只做几何/行为断言（finders + 点击回调），**不装截图装置**——
/// `RenderRepaintBoundary.toImage()` 在无合成器的 widget 测试里永不完成。
///
/// ADR-0100 反转了这张卡的职责：从「逐槽铺选项 chip」改为「一句补齐」——
/// 断言的重点也随之下移：**不许**再出现选项 chip，示例句必须一次发全。
void main() {
  Widget harness(AssistantClarifyCard card) => ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (_) => CupertinoApp(
          home: ShadToaster(
            child: SingleChildScrollView(child: card),
          ),
        ),
      );

  List<ClarifySlot> requiredSlots() => const [
        ClarifySlot(
          name: 'subject',
          prompt: '请问要出哪个科目？',
          type: 'enum',
          values: ['数学', '语文', '英语'],
        ),
        ClarifySlot(
          name: 'grade',
          prompt: '几年级？（1-9）',
          type: 'int',
          min: 1,
          max: 9,
        ),
        ClarifySlot(
          name: 'qtype',
          prompt: '要什么题型？',
          type: 'enum',
          values: ['choice', 'fill', 'calc', 'open'],
        ),
      ];

  testWidgets('不给选项 chip —— 补槽不该逼用户点三次', (tester) async {
    await tester.pumpWidget(
      harness(
        AssistantClarifyCard(slots: requiredSlots(), onPrompt: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    // 科目的三个枚举值 / 年级的 9 个数字 / 题型的四个中文标签都不该铺成选项。
    for (final leak in ['语文', '英语', '选择题', '填空题', '1', '9']) {
      expect(find.text(leak), findsNothing,
          reason: 'ADR-0100：选项 chip 已移除，$leak 不该单独渲染成可点项');
    }
  });

  testWidgets('点示例句：一次发全三个槽的值', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      harness(
        AssistantClarifyCard(slots: requiredSlots(), onPrompt: sent.add),
      ),
    );
    await tester.pumpAndSettle();

    // 示例句必须在一处文本里可见（用户要能照抄），且整卡可点。
    expect(find.textContaining(AssistantClarifyCard.example), findsOneWidget);

    await tester.tap(find.textContaining(AssistantClarifyCard.example));
    await tester.pumpAndSettle();

    // 一次回执同时含科目 / 年级 / 题型——后端 fill_slots 按正则一次抽满。
    expect(sent, hasLength(1));
    expect(sent.single, contains('数学'));
    expect(sent.single, contains('三年级'));
    expect(sent.single, contains('选择题'));
  });

  testWidgets('无缺槽 → 不渲染任何东西', (tester) async {
    await tester.pumpWidget(
      harness(
        AssistantClarifyCard(slots: const <ClarifySlot>[], onPrompt: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(AssistantClarifyCard.example), findsNothing);
  });

  testWidgets('示例句覆盖不到的缺槽 → 不渲染按钮（避免补错值）', (tester) async {
    await tester.pumpWidget(
      harness(
        AssistantClarifyCard(
          slots: const [
            ClarifySlot(
              name: 'knowledge_point',
              prompt: '有指定的知识点吗？',
              type: 'string',
            ),
          ],
          onPrompt: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('一句补齐'), findsNothing,
        reason: '示例句补不出知识点，给了按钮就是「点了补错值」');
  });
}
