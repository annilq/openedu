import '../domain/assistant_card.dart';
import 'widgets/assistant_card_plain_text.dart';
import 'provider/assistant_notifier.dart';

/// 把当前对话压成一份可读的 Markdown 文本，供「导出对话」落盘（file_picker.saveFile）。
///
/// 用户消息标「我」、AI 消息标「AI 老师」；卡片（题卡 / 任务卡 / 学情卡）经 [cardPlainText]
/// 转成纯文本一并导出——可见内容都进文件，避免「导出了却看不到题」。占位「思考中」
/// 气泡无正文、导出中途不会残留，直接跳过；被安全限制的回复标一句提示而非丢内容。
String buildConversationMarkdown(List<AssistantMessage> messages) {
  final buffer = StringBuffer();
  buffer.writeln('# AI 对话记录');
  buffer.writeln();
  buffer.writeln('导出时间：${_exportStamp()}');
  buffer.writeln();

  var hasContent = false;
  for (final m in messages) {
    if (m.thinking) continue;
    final text = m.text.trim();
    final cardText = (m.cards ?? const <AssistantCard>[])
        .map(cardPlainText)
        .where((s) => s.trim().isNotEmpty)
        .join('\n\n');
    if (text.isEmpty && cardText.isEmpty) continue;

    final who = m.role == 'user' ? '我' : 'AI 老师';
    buffer.writeln('**$who：**');
    buffer.writeln();
    if (m.blocked) {
      buffer.writeln('（内容已被安全限制）');
    } else {
      if (text.isNotEmpty) buffer.writeln(text);
      if (cardText.isNotEmpty) {
        if (text.isNotEmpty) buffer.writeln();
        buffer.writeln(cardText);
      }
    }
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    hasContent = true;
  }

  if (!hasContent) return '# AI 对话记录\n\n（暂无内容）\n';
  return buffer.toString();
}

String _exportStamp() {
  final d = DateTime.now().toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}

/// 导出文件名用的日期戳（YYYY-MM-DD_HHmm），避免中文/空格导致保存面板默认名异常。
String conversationFileNameStamp() {
  final d = DateTime.now().toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}_${p(d.hour)}${p(d.minute)}';
}
