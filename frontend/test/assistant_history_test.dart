// 守住 ADR-0048（归属口径经 ADR-0096 收敛）：助手页内的「历史会话」。
//
// 断言的是**行为**而不是「渲染了某个组件」：
// - 列表里每一条点开都进入**续接**（有输入框、气泡带进对话区）；
// - 不再有「只读回放」那一态——后端只返回本人可见的会话，每条都可续接；
// - 学生端也有历史入口（ADR-0048 曾把它定为教师专属，那条理由已不成立）。
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/features/assistant/domain/assistant_card.dart';
import 'package:kids_learn/features/assistant/domain/assistant_event.dart';
import 'package:kids_learn/features/assistant/domain/assistant_requests.dart';
import 'package:kids_learn/features/assistant/domain/conversation.dart';
import 'package:kids_learn/features/assistant/presentation/screens/assistant_chat_page.dart';
import 'package:kids_learn/features/assistant/providers/assistant_provider.dart';
import 'package:kids_learn/shared/theme/app_theme.dart';
import 'package:kids_learn/shared/widgets/app_actions.dart';

const _mine = AssistantConversation(
  id: 'me-1',
  title: '我都有哪些娃',
  kind: 'query',
  bubbleCount: 2,
  updatedAt: '2026-09-15T12:00:00+00:00',
);

/// 另一段**同一个人的**会话（ADR-0096 前它是「学生的会话」，归属口径已变）。
const _other = AssistantConversation(
  id: 'other-1',
  title: '23 + 45 怎么算',
  kind: 'tutor',
  bubbleCount: 4,
  updatedAt: '2026-09-16T01:30:00+00:00',
);

const _mineDetail = AssistantConversationDetail(
  conversation: _mine,
  bubbles: [
    AssistantBubble(role: 'user', text: '我都有哪些娃'),
    AssistantBubble(role: 'assistant', text: '你有 2 个学生。'),
  ],
);

const _otherDetail = AssistantConversationDetail(
  conversation: _other,
  bubbles: [
    AssistantBubble(role: 'user', text: '23 + 45 怎么算'),
    AssistantBubble(role: 'assistant', text: '先看清条件，再选方法。'),
  ],
);

/// 假仓库：只做「列表 + 单段回放 + 删除 + 延后删除」，并记下被打开 / 被删除的会话 id。
///
/// [scheduleDelete] / [cancelScheduledDelete] 用真 [Timer] 复刻仓库行为，
/// 这样测试能靠 `tester.pump` 推进假时钟，验证「5 秒窗口内可撤销、到期才真删」。
class _FakeAssistant extends Fake implements AssistantRepository {
  _FakeAssistant({this.items = const [_other, _mine]});

  final List<AssistantConversation> items;
  final List<String> opened = [];
  final List<String> deletedIds = [];

  final Map<String, _ScheduledDelete> _scheduled = {};
  int _seq = 0;

  @override
  Future<List<AssistantConversation>> conversations() async => items;

  @override
  Future<AssistantConversationDetail> conversationDetail(String id) async {
    opened.add(id);
    return id == 'me-1' ? _mineDetail : _otherDetail;
  }

  @override
  Future<int> deleteConversations(List<String> ids) async {
    deletedIds.addAll(ids);
    return ids.length;
  }

  @override
  ScheduledDeleteHandle scheduleDelete(
    List<String> ids, {
    required Future<void> Function() onConfirm,
    Duration window = const Duration(seconds: 5),
  }) {
    final id = 'sd-${++_seq}';
    _scheduled[id] = _ScheduledDelete(
      ids: ids,
      onConfirm: onConfirm,
      timer: Timer(window, () {
        _scheduled.remove(id);
        onConfirm();
      }),
    );
    return ScheduledDeleteHandle(id: id, ids: ids);
  }

  @override
  bool cancelScheduledDelete(String handleId) {
    final e = _scheduled.remove(handleId);
    if (e == null) return false;
    e.timer.cancel();
    return true;
  }

  @override
  Stream<AssistantEvent> chat(AssistantChatReq req) => const Stream.empty();
}

/// 测试用：窗口内待执行的延后删除。
class _ScheduledDelete {
  _ScheduledDelete({
    required this.ids,
    required this.onConfirm,
    required this.timer,
  });

  final List<String> ids;
  final Future<void> Function() onConfirm;
  final Timer timer;
}

/// 带「题目卡片」的假仓库（Task 2 守卫：续接要连卡片一起显示，不只是 text）。
class _FakeCardRepo extends _FakeAssistant {
  _FakeCardRepo() : super(items: const [_other]);

  @override
  Future<AssistantConversationDetail> conversationDetail(String id) async {
    opened.add(id);
    return AssistantConversationDetail(
      conversation: _other,
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

/// 带「追问卡 / 汇总卡」结构化帧的假仓库（ADR-0095 回放守卫）。
///
/// 气泡载荷里存的就是与实时流 `extra` 同形的 clarify / summary map——续接一段
/// 发生过缺槽追问的旧会话时，卡必须按原样还原，而不是退化成一句裸文本。
class _FakeSlotRepo extends _FakeAssistant {
  _FakeSlotRepo() : super(items: const [_other]);

  @override
  Future<AssistantConversationDetail> conversationDetail(String id) async {
    opened.add(id);
    return AssistantConversationDetail(
      conversation: _other,
      bubbles: const [
        AssistantBubble(role: 'user', text: '出几道数学题'),
        AssistantBubble(
          role: 'assistant',
          text: '请告诉我几年级、要什么题型',
          clarify: {
            'missing_slots': [
              {
                'name': 'grade',
                'prompt': '几年级？（1-9）',
                'type': 'int',
                'min': 1,
                'max': 9,
              },
              {
                'name': 'qtype',
                'prompt': '要什么题型？',
                'type': 'enum',
                'enum': ['choice', 'fill', 'calc', 'open'],
              },
            ],
          },
        ),
        AssistantBubble(role: 'user', text: '三年级出选择题'),
        AssistantBubble(
          role: 'assistant',
          text: '已确认规格：科目=数学，年级=3，题型=选择题',
          summary: {
            'slots': [
              {
                'name': 'subject',
                'label': '科目',
                'type': 'enum',
                'enum': ['数学', '语文'],
                'value': '数学',
                'value_label': '数学',
              },
              {
                'name': 'qtype',
                'label': '题型',
                'type': 'enum',
                'enum': ['choice', 'fill', 'calc', 'open'],
                'value': 'choice',
                'value_label': '选择题',
              },
            ],
          },
        ),
      ],
    );
  }
}

void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    _FakeAssistant repo, {
    bool isTeacher = true,
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
          theme: AppTheme.shadFor(false, AppUserMode.teacher, AppDensity.compact),
          appBuilder: (context) => CupertinoApp(
            // 与线上一致：线上由 CupertinoApp.builder 内的 ShadAppBuilder 提供
            // `ShadToaster`；测试直接包一层等价的 `ShadToaster`，否则 `AppToast.show`
            // 会抛「找不到 ShadToaster」，删除成功的提示无法断言。
            builder: (context, child) =>
                ShadToaster(child: child ?? const SizedBox.shrink()),
            home: AssistantChatPage(showBack: showBack, isTeacher: isTeacher),
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

  testWidgets('顶栏有历史入口，点开进入历史列表', (tester) async {
    await pumpPage(tester, _FakeAssistant());
    expect(find.text('AI 学习助手'), findsOneWidget);

    await openHistory(tester);

    expect(find.text('历史会话'), findsOneWidget);
    expect(find.text('我都有哪些娃'), findsOneWidget);
    expect(find.text('23 + 45 怎么算'), findsOneWidget);
    expect(find.text('只读'), findsNothing,
        reason: '列表里每条都可续接，不再有只读条目与只读徽标（ADR-0096）');
  });

  testWidgets('列表按后端顺序原样铺开（最近活动的在前）', (tester) async {
    // 装置里 23+45 那段更近（排在前面），前端不重排、也不再分组。
    await pumpPage(tester, _FakeAssistant());
    await openHistory(tester);

    final otherY = tester.getTopLeft(find.text('23 + 45 怎么算')).dy;
    final mineY = tester.getTopLeft(find.text('我都有哪些娃')).dy;
    expect(otherY, lessThan(mineY), reason: '后端已按 updated_at 倒序，前端原样渲染');
  });

  testWidgets('点我的会话：回到对话模式，历史气泡就在里面（可续接）', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('我都有哪些娃'));
    await tester.pumpAndSettle();

    expect(repo.opened, ['me-1'], reason: '必须按 id 取会话载荷，而不是拿列表里的字段拼');
    expect(find.text('历史会话'), findsNothing);
    expect(find.text('AI 学习助手'), findsOneWidget);
    expect(find.text('我都有哪些娃'), findsOneWidget,
        reason: '历史气泡应进入对话区，用户可以接着聊');
    expect(find.byType(ShadInput), findsOneWidget, reason: '自己的会话可以继续提问');
  });

  testWidgets('点任一段会话：都是续接——有气泡、有输入框', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('23 + 45 怎么算'));
    await tester.pumpAndSettle();

    expect(repo.opened, ['other-1']);
    expect(find.text('23 + 45 怎么算'), findsOneWidget, reason: '历史气泡要看得到');
    expect(find.byType(ShadInput), findsOneWidget,
        reason: 'ADR-0096：列表里每条都是本人的会话，都能接着问');
  });

  testWidgets('续接后可退回列表，再从列表回到对话', (tester) async {
    await pumpPage(tester, _FakeAssistant());
    await openHistory(tester);
    await tester.tap(find.text('23 + 45 怎么算'));
    await tester.pumpAndSettle();

    // 顶栏「历史」回到列表（页内切模式，不是 pop 整页）
    await openHistory(tester);
    expect(find.text('历史会话'), findsOneWidget);

    // 返回键回对话
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
    // 教师口径空态：文案在 ADR-0054 里改成「只说做得到的」——原文案
    // 「一句话就能布置任务」是做不到的承诺（助手只读），正是那次报障的预期来源。
    expect(find.text('可以出题、查学情、看错题'), findsOneWidget, reason: '回到教师口径的空态');
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

  testWidgets('学生端也有历史入口（ADR-0096 反转了「教师专属」）', (tester) async {
    await pumpPage(tester, _FakeAssistant(), isTeacher: false);

    expect(find.text('问 AI 老师'), findsOneWidget);
    expect(find.byIcon(LucideIcons.history), findsOneWidget,
        reason: '后端按调用者身份返回本人可见的会话，学生看到的就是自己问过的');
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

    await tester.tap(find.text('多选'));
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
    // 「已选 N 项」同时出现在顶栏标题与列表操作条，所以文本会命中 2 处；这里只验存在。
    expect(find.text('已选 1 项'), findsWidgets);

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

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    // 「已选 N 项」同时出现在顶栏标题与列表操作条，文本命中 2 处；这里只验存在。
    expect(find.text('已选 2 项'), findsWidgets,
        reason: '默认列表 2 段，全选应全中');
    expect(find.byIcon(LucideIcons.checkCircle2), findsNWidgets(2));

    // 全选后按钮变「取消全选」，再点一次清空。
    await tester.tap(find.text('取消全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);
  });

  testWidgets('删除选中会话：确认弹窗 → 延后 5 秒才真删后端 → 退出多选', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('多选'));
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

    // 确认后立刻给出口（「已删除 + 撤销」），但窗口内不真删后端。
    expect(find.text('已删除 1 段会话'), findsOneWidget, reason: '立即给出口');
    expect(find.text('撤销'), findsOneWidget, reason: '提供 5 秒撤销入口');
    expect(repo.deletedIds, isEmpty, reason: '窗口内不碰后端，到期才真删');
    // 退出多选：勾选框消失、恢复「管理」入口、顶栏不再是删除按钮。
    expect(find.byIcon(LucideIcons.circle), findsNothing);
    expect(find.byIcon(LucideIcons.trash2), findsNothing);
    expect(find.text('多选'), findsOneWidget);

    // 5 秒到期 → 才真删后端。
    await tester.pump(Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(repo.deletedIds, unorderedEquals(['me-1']),
        reason: '到期才把选中的那段按 id 交给后端（归属校验在服务端）');
  });

  testWidgets('删除后 5 秒内撤销：不真删后端，列表保持原样', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我都有哪些娃'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.trash2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, isEmpty, reason: '确认后窗口内不真删');

    // 点 toast「撤销」→ 取消定时器。
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    // 即便等过 5 秒窗口，删除仍不应发生（Timer 已取消）。
    await tester.pump(Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(repo.deletedIds, isEmpty, reason: '撤销后 Timer 被取消，不真删');
    // 列表保持原样（项仍在）。
    expect(find.text('我都有哪些娃'), findsOneWidget, reason: '撤销后列表恢复');
  });

  testWidgets('删除后 5 秒到期：才真删后端', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我都有哪些娃'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.trash2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 窗口内尚未真删。
    expect(repo.deletedIds, isEmpty);

    // 推进 5 秒（假时钟）→ 定时器到点，回调真删。
    await tester.pump(Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(repo.deletedIds, unorderedEquals(['me-1']),
        reason: '到期才真删后端，给误删兜底');
  });

  testWidgets('未选中任何会话时，删除按钮禁用', (tester) async {
    final repo = _FakeAssistant();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();

    // 没选任何行：顶栏删除按钮存在但不可用（onPressed == null）。
    final actionFinder = find.byWidgetPredicate(
      (w) => w is AppIconAction && w.icon == LucideIcons.trash2,
    );
    expect(actionFinder, findsOneWidget);
    final action = tester.widget<AppIconAction>(actionFinder);
    expect(action.onPressed, isNull, reason: '空选时删除不应可点');
  });

  // ── 会话卡片（Task 2） ────────────────────────────────────────────────
  testWidgets('续接包含题目卡片（不只是 text）', (tester) async {
    // 守卫 ADR-0042：会话载荷里的 DATA 卡片必须连题干一起渲染，不能只显示文本。
    final repo = _FakeCardRepo();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('23 + 45 怎么算'));
    await tester.pumpAndSettle();

    // 题目卡片渲染出来了：题干文本只可能来自卡片（气泡正文是「好的，这道题给你：」）。
    expect(find.text('1 + 1 等于多少？'), findsOneWidget,
        reason: '题目卡片的题干应显示在续接的对话区里，而不是只显示文本气泡');
    expect(find.text('数学'), findsWidgets, reason: '学科标签随卡片一起出现');
    // 文本气泡也在：卡片之外，正文照常显示。
    expect(find.text('好的，这道题给你：'), findsOneWidget);
  });

  // ── 追问卡 / 汇总卡的回放还原（ADR-0095） ─────────────────────────────
  testWidgets('续接还原追问卡与汇总卡（不是裸文本）', (tester) async {
    // 落库存的就是与实时流 extra 同形的结构化帧；只搬 text 会让历史里的
    // 「请告诉我年级」退化成光秃秃一句，用户看不到当初的可点选项。
    final repo = _FakeSlotRepo();
    await pumpPage(tester, repo);
    await openHistory(tester);

    await tester.tap(find.text('23 + 45 怎么算'));
    await tester.pumpAndSettle();

    // 追问卡：标题 + 两个槽的 prompt + 年级数字 chip 都在
    expect(find.text('还差这些信息：'), findsOneWidget);
    expect(find.text('几年级？（1-9）'), findsOneWidget);
    expect(find.text('要什么题型？'), findsOneWidget);
    expect(find.text('选择题'), findsWidgets, reason: 'enum 槽铺中文选项 chip');

    // 汇总卡：逐项列出已确认规格
    expect(find.text('已确认规格：'), findsOneWidget);
    expect(find.text('科目'), findsOneWidget);
    expect(find.text('题型'), findsOneWidget);
  });

  testWidgets('回放的追问卡仍可点：值作为新消息发回本会话', (tester) async {
    // 归属收敛后每条历史会话都是本人的、都可续接——追问卡不是静态展板，
    // 点 chip 等于接着补槽，后端按同一套 fill_slots 合并。
    final repo = _FakeSlotRepo();
    await pumpPage(tester, repo);
    await openHistory(tester);
    await tester.tap(find.text('23 + 45 怎么算'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    expect(find.text('3年级'), findsOneWidget,
        reason: '点年级 chip 后该值作为一条用户消息进入对话区');
    expect(find.byType(ShadInput), findsOneWidget, reason: '仍在本会话内，可继续输入');
  });
}
