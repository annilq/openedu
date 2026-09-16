// 守住 ADR-0048：助手页内的「历史会话 + 只读回放」。
//
// 断言的是**行为分叉**而不是「渲染了某个组件」：
// - 我的会话点开 → 回到对话模式且历史气泡在里面（可以接着聊）；
// - 孩子的会话点开 → 只读回放（没有输入框），并说明为什么不能输入。
// 第二条是这套设计的核心约束：拿孩子的 session_id 去续接会被后端归属校验拒掉并
// 另建一段会话，而屏幕上看起来像续上了。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_event.dart';
import 'package:kids_learn/features/assistant/domain/assistant_requests.dart';
import 'package:kids_learn/features/assistant/domain/conversation.dart';
import 'package:kids_learn/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:kids_learn/features/assistant/presentation/screens/assistant_chat_page.dart';
import 'package:kids_learn/features/assistant/providers/assistant_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';

const _mine = AssistantConversation(
  id: 'me-1',
  title: '我都有哪些娃',
  kind: 'query',
  bubbleCount: 2,
  updatedAt: '2026-09-15T12:00:00+00:00',
);

const _kid = AssistantConversation(
  id: 'kid-1',
  title: '23 + 45 怎么算',
  kind: 'tutor',
  childId: 'child-1',
  childName: '小明',
  bubbleCount: 4,
  updatedAt: '2026-09-16T01:30:00+00:00',
);

const _mineDetail = AssistantConversationDetail(
  conversation: _mine,
  bubbles: [
    AssistantBubble(role: 'user', text: '我都有哪些娃'),
    AssistantBubble(role: 'assistant', text: '你有 2 个孩子。'),
  ],
);

const _kidDetail = AssistantConversationDetail(
  conversation: _kid,
  bubbles: [
    AssistantBubble(role: 'user', text: '23 + 45 怎么算'),
    AssistantBubble(role: 'assistant', text: '先看清条件，再选方法。'),
  ],
);

/// 假仓库：只做「列表 + 单段回放」，并记下被打开过的会话 id。
class _FakeAssistant extends Fake implements AssistantRepository {
  _FakeAssistant({this.items = const [_kid, _mine]});

  final List<AssistantConversation> items;
  final List<String> opened = [];

  @override
  Future<List<AssistantConversation>> conversations() async => items;

  @override
  Future<AssistantConversationDetail> conversationDetail(String id) async {
    opened.add(id);
    return id == 'me-1' ? _mineDetail : _kidDetail;
  }

  @override
  Stream<AssistantEvent> chat(AssistantChatReq req) => const Stream.empty();
}

void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    _FakeAssistant repo, {
    bool isParent = true,
    bool showBack = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [assistantRepositoryProvider.overrideWithValue(repo)],
        // 显式传主题：`ShadApp.custom` 不传会退回 shadcn 默认主题，几何断言量到的是
        // 与产品不符的数（ADR-0046 记录过这个坑）。
        child: ShadApp.custom(
          theme: AppTheme.shadFor(false, AppUserMode.parent, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            home: AssistantChatPage(showBack: showBack, isParent: isParent),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openHistory(WidgetTester tester) async {
    await tester.tap(find.byIcon(LucideIcons.history));
    await tester.pumpAndSettle();
  }

  testWidgets('家长端顶栏有历史入口，点开进入历史列表', (tester) async {
    await pumpPage(tester, _FakeAssistant());
    expect(find.text('AI 学习助手'), findsOneWidget);

    await openHistory(tester);

    expect(find.text('历史会话'), findsOneWidget);
    expect(find.text('我的对话'), findsOneWidget);
    expect(find.text('小明的对话'), findsOneWidget,
        reason: '孩子的会话按娃分段，段名用娃娃显示名');
    expect(find.text('只读'), findsOneWidget, reason: '只读这件事要写在行上，'
        '而不是等用户点进去才发现输入框没了');
  });

  testWidgets('「我的对话」置顶，不受最近活动时间影响', (tester) async {
    // 装置里孩子那段更近（排在前面）——「我的对话」仍应在最上。
    await pumpPage(tester, _FakeAssistant());
    await openHistory(tester);

    final mineY = tester.getTopLeft(find.text('我的对话')).dy;
    final kidY = tester.getTopLeft(find.text('小明的对话')).dy;
    expect(mineY, lessThan(kidY));
  });

  testWidgets('点我的会话：回到对话模式，历史气泡就在里面（可续接）', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('我都有哪些娃'));
    await tester.pumpAndSettle();

    expect(repo.opened, ['me-1'], reason: '必须按 id 取回放载荷，而不是拿列表里的字段拼');
    expect(find.text('历史会话'), findsNothing);
    expect(find.text('AI 学习助手'), findsOneWidget);
    expect(find.text('我都有哪些娃'), findsOneWidget,
        reason: '历史气泡应进入对话区，用户可以接着聊');
    expect(find.byType(ShadInput), findsOneWidget, reason: '自己的会话可以继续提问');
  });

  testWidgets('点孩子的会话：只读回放——有气泡、无输入框、且说明原因', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('23 + 45 怎么算'));
    await tester.pumpAndSettle();

    expect(repo.opened, ['kid-1']);
    expect(find.text('这是小明的对话，只能查看，不能继续提问'), findsOneWidget,
        reason: '输入框被撤掉时必须说明原因，否则用户会以为界面坏了');
    expect(find.byType(ShadInput), findsNothing,
        reason: '孩子的会话不能续接：后端归属校验会另建一段，屏幕上却像续上了');
    expect(find.text('23 + 45 怎么算'), findsOneWidget, reason: '回放气泡要看得到');
  });

  testWidgets('只读回放可退回列表，再从列表回到对话', (tester) async {
    await pumpPage(tester, _FakeAssistant());
    await openHistory(tester);
    await tester.tap(find.text('23 + 45 怎么算'));
    await tester.pumpAndSettle();

    // 返回键（页内返回历史列表，不是 pop 整页）
    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    await tester.pumpAndSettle();
    expect(find.text('历史会话'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    await tester.pumpAndSettle();
    expect(find.text('AI 学习助手'), findsOneWidget);
  });

  testWidgets('「新对话」清掉当前这一段，回到空态', (tester) async {
    await pumpPage(tester, _FakeAssistant());
    await openHistory(tester);
    await tester.tap(find.text('我都有哪些娃'));
    await tester.pumpAndSettle();
    expect(find.text('我都有哪些娃'), findsOneWidget);

    await openHistory(tester);
    await tester.tap(find.byIcon(LucideIcons.squarePen));
    await tester.pumpAndSettle();

    expect(find.text('我都有哪些娃'), findsNothing,
        reason: '不显式断开 session_id 的话，「新对话」只是一句空话');
    expect(find.text('一句话就能布置任务'), findsOneWidget, reason: '回到家长口径的空态');
  });

  testWidgets('历史入口键盘可达：Tab 到它、Enter 进入列表', (tester) async {
    // showBack=false → 顶栏只有一个可点区域，首次 Tab 必然落在它上面。
    await pumpPage(tester, _FakeAssistant(), showBack: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('历史会话'), findsOneWidget,
        reason: '裸 GestureDetector 不在焦点树里——Tab 跳不到、Enter 点不动，'
            '而 flutter analyze 照不出来');
  });

  testWidgets('娃娃端没有历史入口（有意的不对称）', (tester) async {
    await pumpPage(tester, _FakeAssistant(), isParent: false);

    expect(find.text('问 AI 老师'), findsOneWidget);
    expect(find.byIcon(LucideIcons.history), findsNothing,
        reason: '后端没有 child-scoped 会话列表路由；且孩子看到自己「被拦过」的'
            '记录是负面强化——这是有意留的不对称，不是漏做');
  });

  testWidgets('列表为空时给空态而不是白屏', (tester) async {
    await pumpPage(tester, _FakeAssistant(items: const []));
    await openHistory(tester);

    expect(find.text('还没有历史对话'), findsOneWidget);
  });
}
