// 领域模型：与后端 SQLModel schema 对齐的纯 Dart 模型。
// 注意：所有 ID 均为 UUID 字符串（后端用 uuid.UUID）。

/// 游标分页信封（ADR-0053）：题库 / 任务 / 错题本三个长列表共用。
///
/// 翻页只看 [nextCursor]——[nextCursor] 为 null 即到底。**不要用 [total] 判断是否
/// 还有下一页**：total 是取页那一刻的快照，期间插入新数据后必然失真。
/// [total] 只用于「还有 N 条」这类展示。
class CursorPage<T> {
  final List<T> items;
  final int total;
  final int pageSize;

  /// 下一页游标；null = 已到底。不透明字符串，只能原样回传，不得解析。
  final String? nextCursor;

  const CursorPage({
    required this.items,
    required this.total,
    required this.pageSize,
    this.nextCursor,
  });

  bool get hasMore => nextCursor != null;

  /// 已加载条数（追加模式下由调用方累计，不在这里记账）。
  int get loaded => items.length;

  /// 追加下一页：只在 [hasMore] 时调用，返回新信封（items 为累加结果）。
  CursorPage<T> append(CursorPage<T> next) => CursorPage<T>(
        items: [...items, ...next.items],
        total: next.total,
        pageSize: next.pageSize,
        nextCursor: next.nextCursor,
      );

  factory CursorPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) =>
      CursorPage<T>(
        items: (json['items'] as List? ?? [])
            .map((e) => parse(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int? ?? 0,
        pageSize: json['page_size'] as int? ?? 20,
        nextCursor: json['next_cursor'] as String?,
      );
}
