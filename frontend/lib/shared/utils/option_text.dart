/// 选项文本清洗：去掉选项自带的字母前缀（"A. " / "B、" / "（C）"），
/// 字母序号由 [AppOptionTile] 按位置统一生成，避免与选项块自带的 A/B/C 重复。
///
/// 与后端 `export/document.py::strip_option_prefix` 同口径（出题模型常把选项写成
/// "A. 第一个选项"，而 AppOptionTile 自己会渲染 "A" 圆圈，不剥就会变成 "A. A. 第一个选项"）。
/// 注意：仅剥「字母前缀」，选项正文原样保留。
library;

final RegExp _optionPrefix = RegExp(r'^[\(（\[]?[A-Za-z][\)）\].、：:．]\s*');

String cleanOptionText(String option) {
  final text = option.trim();
  if (text.isEmpty) return text;
  return text.replaceFirst(_optionPrefix, '').trim();
}
