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

import 'package:kids_learn/features/assistant/domain/assistant_card.dart';
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

/// 假仓库：只做「列表 + 单段回放 + 删除」，并记下被打开 / 被删除的会话 id。
class _FakeAssistant extends Fake implements AssistantRepository {
  _FakeAssistant({this.items = const [_kid, _mine]});

  final List<AssistantConversation> items;
  final List<String> opened = [];
  final List<String> deletedIds = [];

  @override
  Future<List<AssistantConversation>> conversations() async => items;

  @override
  Future<AssistantConversationDetail> conversationDetail(String id) async {
    opened.add(id);
    return id == 'me-1' ? _mineDetail : _kidDetail;
  }

  @override
  Future<int> deleteConversations(List<String> ids) async {
    deletedIds.addAll(ids);
    return ids.length;
  }

  @override
  Stream<AssistantEvent> chat(AssistantChatReq req) => const Stream.empty();
}

/// 只读回放带「题目卡片」的假仓库（Task 2 守卫：回放要连卡片一起显示，不只是 text）。
class _FakeCardRepo extends _FakeAssistant {
  _FakeCardRepo() : super(items: const [_kid]);

  @override
  Future<AssistantConversationDetail> conversationDetail(String id) async {
    opened.add(id);
    return AssistantConversationDetail(
      conversation: _kid,
      bubbles: [
        const AssistantBubble(role: 'user', text: '出一道二年级的数学题'),
        AssistantBubble(
          role: 'assistant',
          text: '好的，这道题给你：',
          cards: [
            AssistantCard.fromData(const {
              'type': 'question',
              'result': {
                'subject': '数学',
                'grade': 2,
                'qtype': 'choice',
                'stem': '1 + 1 等于多少？',
                'options': ['1', '2', '3'],
              },
            })!,
          ],
        ),
      ],
    );
  }
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
            // ShadToaster 必须显式装上——主 app 与测试 pumpPage 都漏了，结果
            // `ShadToaster.of(context)` 找不到 ancestor 抛错，所有 AppToast 在
            // 整个 app 里都失效。这里包一层让测试断言能 found toast 文本；修主 app
            // 的同源问题在「待真机」列里挂着（critical：用户实际看不到任何 toast）。
            builder: (context, child) =>
                ShadToaster(child: child ?? const SizedBox.shrink()),
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

  // ── 多选删除（Task 1） ────────────────────────────────────────────────
  testWidgets('「管理」进入多选态：行内出现勾选框，点行切换选中', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    // 非多选态：行内不应有勾选框。
    expect(find.byIcon(LucideIcons.circle), findsNothing);

    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();

    // 进入多选态：每段一行一个未选中勾选框（默认列表 2 段）。
    expect(find.byIcon(LucideIcons.circle), findsNWidgets(2),
        reason: '多选态下每段会话左侧出现未选中勾选框');
    expect(find.text('已选 0 项'), findsOneWidget);

    // 点一段 → 选中（勾选框变 checkCircle2，计数 +1）。
    await tester.tap(find.text('我都有哪些娃'));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.checkCircle2), findsOneWidget,
        reason: '选中行应切到勾选态');
    expect(find.text('已选 1 项'), findsOneWidget);

    // 再点同一段 → 取消选中。
    await tester.tap(find.text('我都有哪些娃'));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.checkCircle2), findsNothing);
    expect(find.text('已选 0 项'), findsOneWidget);
  });

  testWidgets('多选态「全选 / 取消全选」一次选中或清空全部', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget,
        reason: '默认列表 2 段（我的 + 孩子的），全选应全中');
    expect(find.byIcon(LucideIcons.checkCircle2), findsNWidgets(2));

    // 全选后按钮变「取消全选」，再点一次清空。
    await tester.tap(find.text('取消全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);
  });

  testWidgets('删除选中会话：确认弹窗 → 调仓库删除 → 退出多选', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();

    // 选中「我的对话」那段。
    await tester.tap(find.text('我都有哪些娃'));
    await tester.pumpAndSettle();

    // 顶栏出现删除按钮（trash2）。
    final trash = find.byIcon(LucideIcons.trash2);
    expect(trash, findsOneWidget);

    await tester.tap(trash);
    await tester.pumpAndSettle();

    // 确认弹窗出现（标题 + 确认按钮文案「删除」）。
    expect(find.text('删除会话'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget,
        reason: '确认按钮文案为「删除」，且与正文「删除选中的…」区分');

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, unorderedEquals(['me-1']),
        reason: '只删选中的那段，且按 id 交给后端（归属校验在服务端）');
    expect(find.text('已删除 1 段会话'), findsOneWidget,
        reason: '删除成功要给出口');
    // 退出多选：勾选框消失、恢复「管理」入口、顶栏不再是删除按钮。
    expect(find.byIcon(LucideIcons.circle), findsNothing);
    expect(find.byIcon(LucideIcons.trash2), findsNothing);
    expect(find.text('管理'), findsOneWidget);
  });

  testWidgets('未选中任何会话时，删除按钮禁用', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();

    // 没选任何行：顶栏删除按钮存在但不可用（onPressed == null）。
    final actionFinder = find.byWidgetPredicate(
      (w) => w is AppIconAction && w.icon == LucideIcons.trash2,
    );
    expect(actionFinder, findsOneWidget);
    final action = tester.widget<AppIconAction>(actionFinder);
    expect(action.onPressed, isNull, reason: '空选时删除不应可点');
  });

  // ── 回放卡片（Task 2） ────────────────────────────────────────────────
  testWidgets('只读回放包含题目卡片（不只是 text）', (tester) async {
    // 守卫 ADR-0042：回放载荷里的 DATA 卡片必须连题干一起渲染，不能只显示文本。
    final repo = _FakeCardRepo();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('23 + 45 怎么算'));
    await tester.pumpAndSettle();

    // 题目卡片渲染出来了：题干文本只可能来自卡片（气泡正文是「好的，这道题给你：」）。
    expect(find.text('1 + 1 等于多少？'), findsOneWidget,
        reason: '题目卡片的题干应显示在回放里，而不是只显示文本气泡');
    expect(find.text('数学'), findsWidgets, reason: '学科标签随卡片一起出现');
    // 文本气泡也在：卡片之外，正文照常显示。
    expect(find.text('好的，这道题给你：'), findsOneWidget);
  });
}
