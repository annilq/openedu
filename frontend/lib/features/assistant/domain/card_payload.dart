import '../../../shared/utils/question_labels.dart';
import 'assistant_card.dart';

/// 卡片 raw payload → 展示值：标量读法 + 明细行投影（ADR-0058 §2）。
///
/// 这些函数合成一个文件，因为它们是**同一件事的几种读法**——「后端给的 Map 怎么
/// 变成一行人能读的字」。拆成 `card_str.dart` / `card_int.dart` 只会让 `cardStr`
/// 被复制到各处；而它们本就是一组共生的读法，不是九个独立概念。
///
/// 视觉渲染（`widgets/assistant_*_card.dart`）与「复制」用的纯文本
/// （`widgets/assistant_card_plain_text.dart`）共用这一份，所以**复制到的内容与
/// 看到的卡片不会各写一套而漂移**（ADR-0042：卡片是可见内容，不该出现
/// 「有卡片却复制不到」）。

/// 明细行标签的语气，决定渲染成哪种 chip。
enum CardTone { normal, info, success, warning, subject }

/// 一条明细 → 主行 + 标签列表。
typedef CardRow = ({String primary, List<(String, CardTone)> tags});

/// payload 里的字符串：null → 空串，并去掉两端空白。
///
/// 后端字段可能缺失、可能是数字、也可能带空白；卡片里到处判空会淹掉排版，
/// 所以一律在这里归一成「空串 = 没有」，调用点只写 `if (x.isNotEmpty)`。
String cardStr(Object? v) => v == null ? '' : '$v'.trim();

int cardInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(cardStr(v)) ?? 0;
}

double cardDouble(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse(cardStr(v)) ?? 0;
}

/// `72.0` → `72`，`72.5` → `72.5`（分数是小数，但整数别显示成 `72.0`）。
String cardTrimZero(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toString();

/// 未知种类明细的主行：按候选键依次取第一个非空值。
String cardFirstOf(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final v = cardStr(item[key]);
    if (v.isNotEmpty) return v;
  }
  return '';
}

/// 一条明细 → 主行 + 标签。未知种类走「通用行」：不丢内容，宁可朴素。
CardRow cardRowOf(String kind, Map<String, dynamic> item) {
  final subject = cardStr(item['subject']);
  switch (kind) {
    case AssistantCardKind.taskList:
      final count = cardInt(item['question_count']);
      final status = cardStr(item['status']);
      return (
        primary: cardStr(item['title']),
        tags: [
          (statusLabel(status), _statusTone(status)),
          if (count > 0) ('$count 题', CardTone.info),
        ],
      );
    case AssistantCardKind.wrongQuestionList:
      return (
        primary: cardStr(item['stem']),
        tags: [
          if (subject.isNotEmpty) (subject, CardTone.subject),
          ('错过 ${cardInt(item['wrong_count'])} 次', CardTone.warning),
        ],
      );
    case AssistantCardKind.dueReviewList:
      return (
        primary: cardStr(item['stem']),
        tags: [
          if (subject.isNotEmpty) (subject, CardTone.subject),
          ('复习阶段 ${cardInt(item['review_stage'])}', CardTone.info),
        ],
      );
    case AssistantCardKind.masteryList:
      final level = cardStr(item['level']);
      final wrong = cardInt(item['active_wrong']);
      return (
        primary: cardStr(item['knowledge_point']),
        tags: [
          if (subject.isNotEmpty) (subject, CardTone.subject),
          ('${cardTrimZero(cardDouble(item['score']))} 分', CardTone.normal),
          if (level.isNotEmpty) (level, CardTone.info),
          if (wrong > 0) ('错题 $wrong', CardTone.warning),
        ],
      );
    case AssistantCardKind.questionBankList:
      final kp = cardStr(item['knowledge_point']);
      final usage = cardInt(item['usage_count']);
      final diff = cardInt(item['difficulty']);
      return (
        primary: cardStr(item['stem']),
        tags: [
          if (subject.isNotEmpty) (subject, CardTone.subject),
          if (kp.isNotEmpty) (kp, CardTone.info),
          if (diff > 0) ('难度 $diff', CardTone.normal),
          if (usage > 0) ('复用 $usage 次', CardTone.success),
        ],
      );
    default:
      final primary = cardFirstOf(
        item,
        const ['stem', 'title', 'name', 'knowledge_point'],
      );
      final rest = item.entries
          .where((e) => e.value is String || e.value is num)
          .where((e) => cardStr(e.value).isNotEmpty && cardStr(e.value) != primary)
          .map((e) => '${e.key}: ${cardStr(e.value)}')
          .take(3);
      return (primary: primary, tags: [for (final r in rest) (r, CardTone.normal)]);
  }
}

/// 指标卡的三（或四）个数字。缺字段按 0 处理——指标卡整张消失比显示 0 更糟。
List<(String, String)> cardStatsOf(AssistantCard card) {
  final stats = card.stats;
  final total = cardInt(stats['total']);
  final correct = cardInt(stats['correct']);
  final accuracy = cardDouble(stats['accuracy']);
  final streak = cardInt(stats['streak_days']);
  final checkin = cardInt(stats['checkin_days']);
  return [
    ('$correct/$total', '答对'),
    ('${(accuracy * 100).round()}%', '正确率'),
    ('$streak 天', '连续打卡'),
    if (checkin > 0) ('$checkin 天', '累计打卡'),
  ];
}

/// 题目卡的纯文本行（复制用）：题干 / 选项 / 答案 / 解析 / 出题思路。
///
/// 题卡载荷没有 title/heading 可言，统一用「题目」当块首，字段行自己带全信息。
List<String> cardQuestionLines(AssistantCard card) {
  final raw = card.rawPayload;
  final lines = <String>[
    if (cardStr(raw['subject']).isNotEmpty ||
        cardStr(raw['qtype']).isNotEmpty ||
        cardStr(raw['difficulty']).isNotEmpty)
      [
        cardStr(raw['subject']),
        if (cardInt(raw['grade']) > 0) '${cardInt(raw['grade'])} 年级',
        if (cardStr(raw['qtype']).isNotEmpty) qtypeLabel(cardStr(raw['qtype'])),
        if (cardStr(raw['difficulty']).isNotEmpty)
          difficultyLabel(cardStr(raw['difficulty'])),
      ].where((e) => e.isNotEmpty).join(' · '),
    if (cardStr(raw['stem']).isNotEmpty) cardStr(raw['stem']),
  ];
  if (raw['options'] is List) {
    final options =
        (raw['options'] as List).map(cardStr).where((o) => o.isNotEmpty).toList();
    for (var i = 0; i < options.length; i++) {
      lines.add('${String.fromCharCode(65 + i)}. ${options[i]}');
    }
  }
  if (cardStr(raw['answer']).isNotEmpty) {
    lines.add('答案：${cardStr(raw['answer'])}');
  }
  if (cardStr(raw['explanation']).isNotEmpty) {
    lines.add('解析：${cardStr(raw['explanation'])}');
  }
  if (cardStr(raw['reasoning']).isNotEmpty) {
    lines.add('出题思路：${cardStr(raw['reasoning'])}');
  }
  return lines;
}

CardTone _statusTone(String status) => switch (status) {
      'done' => CardTone.success,
      'assigned' => CardTone.info,
      _ => CardTone.normal,
    };
