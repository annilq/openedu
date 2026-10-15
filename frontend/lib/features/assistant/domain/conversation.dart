import 'assistant_card.dart';

/// 会话历史（ADR-0048）：教师名下的「一段可续接的多轮对话」。
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

  /// 可见轮次数（提问数 + 回答数），列表行上的「几轮」的来源。
  final int bubbleCount;

  /// 最近活动时间（ISO 串，展示时再格式化——与仓库既有列表页同一口径）。
  final String? updatedAt;

  const AssistantConversation({
    required this.id,
    this.title = '',
    this.kind = '',
    this.bubbleCount = 0,
    this.updatedAt,
  });

  /// 提问次数 = ⌈气泡数 / 2⌉：回答最多与提问一样多，除不尽说明最后一次还没答完。
  int get roundCount => (bubbleCount + 1) ~/ 2;

  factory AssistantConversation.fromJson(Map<String, dynamic> json) =>
      AssistantConversation(
        id: '${json['id']}',
        title: (json['title'] as String?)?.trim() ?? '',
        kind: '${json['kind'] ?? ''}',
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

  /// 缺槽追问的结构化载荷（落库时与 SSE 的 `extra.clarify` 同形，ADR-0095）。
  ///
  /// 回放要还原追问卡就得带上它——只带 `text` 的话，历史里那句「请告诉我年级」
  /// 会退化成光秃秃的文本，用户看不到当初的可点选项。
  final Map<String, dynamic>? clarify;

  /// 规格汇总的结构化载荷（与 SSE 的 `extra.summary` 同形，ADR-0095）。
  final Map<String, dynamic>? summary;

  const AssistantBubble({
    required this.role,
    this.text = '',
    this.cards = const <AssistantCard>[],
    this.clarify,
    this.summary,
  });

  factory AssistantBubble.fromJson(Map<String, dynamic> json) => AssistantBubble(
        role: '${json['role'] ?? ''}',
        text: (json['text'] as String?) ?? '',
        cards: _cardsFrom(json['cards']),
        clarify: _mapOf(json['clarify']),
        summary: _mapOf(json['summary']),
      );
}

/// JSON 里的可选 map 字段：非 map（含 null）一律 None，不抛。
Map<String, dynamic>? _mapOf(Object? raw) =>
    raw is Map ? raw.cast<String, dynamic>() : null;

/// 一次会话的载荷：概要 + 全部气泡。
///
/// 只有一种用途——**恢复续接**（ADR-0096）：后端已按调用者归属过滤，拿到的会话
/// 必然是本人的，加载后就能继续发消息。ADR-0048 的「只读回放」这一读法已删除。
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
