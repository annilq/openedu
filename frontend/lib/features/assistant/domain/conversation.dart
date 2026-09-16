import 'assistant_card.dart';

/// 会话历史（ADR-0048）：家长名下的「一段可续接的多轮对话」。
///
/// 与后端 `app/features/assistant/schemas.py` 的 `AssistantConversationResp` 对应。
/// 三个容易混的概念在这里分清（术语见 `CONTEXT.md`）：
///
/// - **会话**（本类）：一段可续接的多轮对话，列表一行就是一段；
/// - **交换**：会话内的一问一答；
/// - **运行轨迹**：`system/routing` 与 `tool/*` 这些步骤——那是 `/ai/debug/conversations`
///   的投影（审计 / 排障用），**不进气泡**。
class AssistantConversation {
  final String id;

  /// 会话名：后端取首条用户消息截断（历史会话缺 title 时由服务端回落）。
  final String title;

  /// 首轮意图的**展示标签**（`tutor` / `query` / `question` …）。
  ///
  /// 只作标签，**不能当分组或筛选依据**：续接轮不会更新它，一个从答疑开始的会话
  /// 后面聊出什么都不会改这个值。
  final String kind;

  /// `null` = 家长自己的会话（可**续接**）；非空 = 孩子的会话（只能**只读回放**）。
  ///
  /// 这个分叉不是 UX 取舍，是后端语义：家长发请求时 `child_id` 恒为 `None`，
  /// 拿孩子的 session_id 去续接会被归属校验拒掉并**另建一段会话**，而屏幕上看起来
  /// 像续上了——顺带把孩子的消息当成家长的 prompt 历史灌进去。
  final String? childId;

  /// 归属标签（孩子的显示名）；家长自己的会话为 null。
  final String? childName;

  /// 可见轮次数（提问数 + 回答数），列表行上的「几轮」的来源。
  final int bubbleCount;

  /// 最近活动时间（ISO 串，展示时再格式化——与仓库既有列表页同一口径）。
  final String? updatedAt;

  const AssistantConversation({
    required this.id,
    this.title = '',
    this.kind = '',
    this.childId,
    this.childName,
    this.bubbleCount = 0,
    this.updatedAt,
  });

  /// 是否可续接（家长自己聊的）。孩子的会话为 false → 只读回放。
  bool get isMine => childId == null;

  /// 提问次数 = ⌈气泡数 / 2⌉：回答最多与提问一样多，除不尽说明最后一次还没答完。
  int get roundCount => (bubbleCount + 1) ~/ 2;

  factory AssistantConversation.fromJson(Map<String, dynamic> json) =>
      AssistantConversation(
        id: '${json['id']}',
        title: (json['title'] as String?)?.trim() ?? '',
        kind: '${json['kind'] ?? ''}',
        childId: json['child_id'] as String?,
        childName: json['child_name'] as String?,
        bubbleCount: _asInt(json['bubble_count']),
        updatedAt: json['updated_at'] as String?,
      );
}

/// 回放的一条消息气泡。
///
/// 角色口径与后端一致（`user` / `assistant`）；UI 侧的 `ai` 是展示层的写法，
/// 两者的换算收口在 `AssistantMessage.fromBubble`。
class AssistantBubble {
  final String role;
  final String text;

  /// DATA 卡片（整帧：判别键 + 载荷）。认不出的种类由渲染器的降级卡兜住。
  final List<AssistantCard> cards;

  const AssistantBubble({
    required this.role,
    this.text = '',
    this.cards = const <AssistantCard>[],
  });

  factory AssistantBubble.fromJson(Map<String, dynamic> json) => AssistantBubble(
        role: '${json['role'] ?? ''}',
        text: (json['text'] as String?) ?? '',
        cards: _cardsFrom(json['cards']),
      );
}

/// 一次会话的回放载荷：概要 + 全部气泡。
///
/// 只读回放（孩子的会话）与恢复续接（家长自己的会话）拿的是**同一份载荷**——
/// 区别只在「加载后能不能继续发消息」，那是前端的模式状态，不是两种数据。
class AssistantConversationDetail {
  final AssistantConversation conversation;
  final List<AssistantBubble> bubbles;

  const AssistantConversationDetail({
    required this.conversation,
    this.bubbles = const <AssistantBubble>[],
  });

  factory AssistantConversationDetail.fromJson(Map<String, dynamic> json) =>
      AssistantConversationDetail(
        conversation: AssistantConversation.fromJson(
          (json['conversation'] as Map).cast<String, dynamic>(),
        ),
        bubbles: [
          for (final raw in (json['bubbles'] as List? ?? const []))
            if (raw is Map)
              AssistantBubble.fromJson(raw.cast<String, dynamic>()),
        ],
      );
}

/// 卡片列表解析：认不出的条目直接跳过，不因一条坏帧让整段回放打不开。
List<AssistantCard> _cardsFrom(Object? raw) {
  if (raw is! List) return const <AssistantCard>[];
  final out = <AssistantCard>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final card = AssistantCard.fromData(entry.cast<String, dynamic>());
    if (card != null) out.add(card);
  }
  return out;
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}
