// 复现用户报障：历史会话两行，点哪一行都显示同样的两条消息？
//
// 夹具来自真实 app.db（2026-09-16）：
// - 行 1「查询题库中的题目」= 4 条气泡（2 轮）；
// - 行 2「有哪些任务」= 6 条气泡（3 轮）。
// 预期：点行 1 显示 4 条、回列表点行 2 显示 6 条。若两行显示相同内容即复现 bug。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/conversation.dart';
import 'package:kids_learn/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:kids_learn/features/assistant/presentation/screens/assistant_chat_page.dart';
import 'package:kids_learn/features/assistant/providers/assistant_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

class _FakeRepo implements AssistantRepository {
  final Map<String, AssistantConversationDetail> details;

  _FakeRepo(this.details);

  @override
  Future<List<AssistantConversation>> conversations() async => [
        for (final d in details.values) d.conversation,
      ];

  @override
  Future<AssistantConversationDetail> conversationDetail(
    String conversationId,
  ) async =>
      details[conversationId] ??
      (throw StateError('no detail for $conversationId'));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

AssistantConversationDetail _detail({
  required String id,
  required String title,
  required List<(String, String)> bubbles,
}) =>
    AssistantConversationDetail(
      conversation: AssistantConversation(
        id: id,
        title: title,
        kind: 'query',
        bubbleCount: bubbles.length,
        updatedAt: '2026-09-16T12:00:00Z',
      ),
      bubbles: [
        for (final (role, text) in bubbles) AssistantBubble(role: role, text: text),
      ],
    );

void main() {
  final details = <String, AssistantConversationDetail>{
    // 真实数据：两段会话气泡数不同（4 vs 6），内容不同。
    '67c8402a-191e-4e07-8467-84fd5a6a8186': _detail(
      id: '67c8402a-191e-4e07-8467-84fd5a6a8186',
      title: '查询题库中的题目',
      bubbles: const [
        ('user', '查询题库中的题目'),
        ('assistant', '题库中共查到 3 道题目，分别是英语、语文、数学各 1 道。'),
        ('user', '查询英语题目'),
        ('assistant', '题库中只查到 1 道英语题目。'),
      ],
    ),
    '9320488e-5cf1-45bc-a9d4-38f550b2cc49': _detail(
      id: '9320488e-5cf1-45bc-a9d4-38f550b2cc49',
      title: '有哪些任务',
      bubbles: const [
        ('user', '有哪些任务'),
        ('assistant', '您家宝宝 lsc 名下有 4 个任务。'),
        ('user', '有哪些题目'),
        ('assistant', '我可以帮您查两类题目数据。'),
        ('user', '题库有哪些题目'),
        ('assistant', '「题库」本身我这边没有对应的查询工具。'),
      ],
    ),
  };

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantRepositoryProvider.overrideWithValue(_FakeRepo(details)),
        ],
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            home: const AssistantChatPage(showBack: true, isParent: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openHistory(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('历史会话'));
    await tester.pumpAndSettle();
  }

  testWidgets('点行 1 显示 4 条气泡，点行 2 显示 6 条（内容互不相同）', (tester) async {
    await pumpPage(tester);
    await openHistory(tester);

    // ── 行 1 ──
    await tester.tap(find.text('查询题库中的题目'));
    await tester.pumpAndSettle();
    expect(find.text('查询题库中的题目'), findsWidgets); // 标题行消失，气泡出现
    expect(find.textContaining('题库中共查到 3 道题目'), findsOneWidget);
    expect(find.text('查询英语题目'), findsOneWidget);
    expect(find.textContaining('只查到 1 道英语题目'), findsOneWidget);
    // 行 2 的内容不该出现
    expect(find.text('有哪些任务'), findsNothing);
    expect(find.text('题库有哪些题目'), findsNothing);

    // ── 回历史列表（chat 态顶栏的 history 入口）再点行 2 ──
    await openHistory(tester);
    await tester.tap(find.text('有哪些任务'));
    await tester.pumpAndSettle();

    // 行 2 应显示自己的 6 条气泡（3 轮），而不是行 1 的内容。
    expect(find.text('有哪些任务'), findsWidgets);
    expect(find.textContaining('名下有 4 个任务'), findsOneWidget);
    expect(find.text('有哪些题目'), findsOneWidget);
    expect(find.text('题库有哪些题目'), findsOneWidget);
    expect(find.textContaining('没有对应的查询工具'), findsOneWidget);
    // 行 1 的内容不该出现
    expect(find.text('查询英语题目'), findsNothing);
    expect(find.textContaining('题库中共查到'), findsNothing);
  });
}
