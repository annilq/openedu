import 'dart:typed_data';

/// 打印导出的请求契约（ADR-0052 · CONTEXT.md §打印导出）。
///
/// **装配在服务端**：客户端只声明「从哪个来源选了哪些东西」，题号、分节、
/// 作答留白、纯文本降级全部由服务端装配好后交给 Typst。客户端不解释模板、
/// 也不拼展示串——这与 ADR-0042 的精神一致：PDF 是最终产物，不是 UI schema。
///
/// - `bank`：[ids] 是题目 id（题库页多选）。
/// - `task`：[ids] 是任务 id（任务页多选，纸上印的是深拷贝快照）。
/// - `wrong_book`：[childId] 必填；[dueOnly] 为 true 时只导今天到期的项。
class ExportSheetRequest {
  final String source;
  final List<String> ids;
  final String? childId;
  final bool dueOnly;
  final String? title;

  const ExportSheetRequest({
    required this.source,
    this.ids = const [],
    this.childId,
    this.dueOnly = false,
    this.title,
  });

  Map<String, dynamic> toJson() => {
        'source': source,
        'ids': ids,
        if (childId != null) 'child_id': childId,
        'due_only': dueOnly,
        if (title != null) 'title': title,
      };
}

/// 单次导出题量的**软提示**阈值（服务端另有硬边界）。
///
/// 家长要印 100 题的复习卷是合理需求，所以超过只提示「建议分批」、允许继续；
/// 拦截是服务端的事，客户端不替服务端做决定。
const int kExportSoftLimit = 60;

/// 判断一段题面文本是否含本轮纸面不支持的内容（公式 `$...$` 或图片 `![..](..)`）。
///
/// 这类题在导出 PDF 里会**按纯文本打印**（定界符被剥掉、保留内部文本）。
/// 客户端手里本来就有题面数据，降级题数由客户端自算并如实提示，
/// 不新增响应头、不给协议加字段。
bool looksLikeRichText(String? text) {
  if (text == null || text.isEmpty) return false;
  return text.contains(r'$') || text.contains('![');
}

/// 统计一组题面里会降级的题数：一道题的题干或任一选项命中即算一道。
int countDowngradedQuestions({
  required Iterable<String> stems,
  Iterable<List<String>?> optionLists = const [],
}) {
  final stemList = stems.toList();
  final optionList = optionLists.toList();
  var count = 0;
  for (var i = 0; i < stemList.length; i++) {
    final degraded = looksLikeRichText(stemList[i]) ||
        (i < optionList.length &&
            (optionList[i] ?? const []).any(looksLikeRichText));
    if (degraded) count++;
  }
  return count;
}

/// 导出仓库抽象：拿回那份将要预览 / 打印 / 分享的 PDF 字节。
abstract class ExportRepository {
  Future<Uint8List> exportSheet(ExportSheetRequest request);
}
