import '../../domain/assistant_card.dart';
import '../../domain/card_payload.dart';

/// 卡片的可复制纯文本（「复制」按钮用）。
///
/// 与视觉渲染共用 [cardRowOf] / [cardStatsOf]，所以「复制到的内容」与「看到的卡片」
/// 不会各写一套而漂移。卡片是可见内容，不该出现「有卡片却复制不到」。
String cardPlainText(AssistantCard card) {
  final head = [card.title, card.subject].where((e) => e.isNotEmpty).join(' · ');
  final lines = <String>[if (head.isNotEmpty) '【$head】'];

  if (card.kind == AssistantCardKind.question) {
    // 题卡载荷没有 title/heading 可言，统一用「题目」当块首，字段行自己带全信息。
    return ['【题目】', ...cardQuestionLines(card)].join('\n');
  }

  if (card.kind == AssistantCardKind.progress) {
    final stats = cardStatsOf(card).map((s) => '${s.$2} ${s.$1}').join(' · ');
    if (stats.isNotEmpty) lines.add(stats);
    if (card.text.isNotEmpty) lines.add(card.text);
    return lines.join('\n');
  }

  if (card.text.isNotEmpty) lines.add(card.text);
  for (var i = 0; i < card.items.length; i++) {
    final row = cardRowOf(card.kind, card.items[i]);
    final tags = row.tags.map((t) => t.$1).join(' · ');
    lines.add('${i + 1}. ${row.primary}${tags.isEmpty ? '' : '（$tags）'}');
  }
  if (card.total > card.items.length) lines.add('…共 ${card.total} 条');
  return lines.join('\n');
}
