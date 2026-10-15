import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_clarify.dart';
import 'package:kids_learn/features/assistant/presentation/widgets/assistant_clarify_card.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

/// 缺槽引导输入卡（ADR-0095）。
///
/// 只做几何/行为断言（finders + 点击回调），**不装截图装置**——
/// `RenderRepaintBoundary.toImage()` 在无合成器的 widget 测试里永不完成。
void main() {
  Widget harness(AssistantClarifyCard card) => ShadApp.custom(
        theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
        appBuilder: (_) => CupertinoApp(
          home: ShadToaster(
            child: SingleChildScrollView(child: card),
          ),
        ),
      );

  testWidgets('枚举槽渲染中文选项并回传原始枚举码', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      harness(
        AssistantClarifyCard(
          slots: const [
            ClarifySlot(
              name: 'qtype',
              prompt: '要什么题型？',
              type: 'enum',
              values: ['choice', 'fill', 'calc', 'open'],
            ),
          ],
          onPrompt: sent.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还差这些信息：'), findsOneWidget);
    expect(find.text('要什么题型？'), findsOneWidget);
    // 展示中文标签、回传后端枚举码（后端按码或中文关键词都能解析）
    expect(find.text('选择题'), findsOneWidget);
    expect(find.text('填空题'), findsOneWidget);

    await tester.tap(find.text('选择题'));
    await tester.pumpAndSettle();
    expect(sent, ['choice']);
  });

  testWidgets('年级 int 槽铺 1-9 选项，点「3」回传「3年级」', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      harness(
        AssistantClarifyCard(
          slots: const [
            ClarifySlot(
              name: 'grade',
              prompt: '几年级？（1-9）',
              type: 'int',
              min: 1,
              max: 9,
            ),
          ],
          onPrompt: sent.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('几年级？（1-9）'), findsOneWidget);
    // min..max 全铺：9 个数字 chip，不需要用户手打
    for (var g = 1; g <= 9; g++) {
      expect(find.text('$g'), findsOneWidget);
    }

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    // 年级要说成「3年级」——后端按「N年级」正则抽取，光发「3」抽不到
    expect(sent, ['3年级']);
  });

  testWidgets('无缺槽 → 不渲染任何东西', (tester) async {
    await tester.pumpWidget(
      harness(
        AssistantClarifyCard(
          slots: const <ClarifySlot>[],
          onPrompt: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还差这些信息：'), findsNothing);
  });
}
