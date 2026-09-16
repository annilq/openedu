/// ISO 串 → "MM-DD HH:mm"（本地时区）。用于列表行的时间显示。
///
/// 后端返回 UTC（`+00:00`），直接截字符串会把晚上九点显示成下午一点；仓库里
/// `wrong_questions_screen` 已有 `toLocal()` 的先例，这里沿用。解析不了就返回空串
/// ——列表宁可少一段元信息，也不该显示一串原始时间戳。
String formatLocalDayMinute(String iso) {
  if (iso.isEmpty) return '';
  final local = DateTime.tryParse(iso)?.toLocal();
  if (local == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
