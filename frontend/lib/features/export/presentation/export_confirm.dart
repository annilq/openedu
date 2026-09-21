import 'package:flutter/widgets.dart';

import '../../../shared/widgets/app_dialog.dart';
import '../domain/export_repository.dart';

/// 导出前的「题目较多」软提示（ADR-0052）。
///
/// 两处导出入口（题库 / 任务）原本各写一份同样的确认弹窗，只有「题目 / 任务」
/// 一个词不同——ADR-0058 的 Rule of Two：第二次抄就得收口。
///
/// ⚠️ **只收口确认弹窗，不收口 `Navigator.push`**：`ExportPreviewPage` 属于
/// `features/export`，`shared/` 不得 import `features/`（ADR-0037），所以这个
/// 文件也落在 export feature 内，而不是 `shared/widgets/`。跳转与装配请求仍然
/// 留在调用点——两边传给服务端的 `source` / `title` / `downgradedCount` 本来就不同。
///
/// 返回 `true` = 继续导出；`false` = 用户取消。**未超软上限时直接返回 true**，
/// 不弹窗（软提示不硬拦：家长要印 100 题的复习卷是合理需求，服务端另有硬边界）。
Future<bool> confirmLargeExport(
  BuildContext context, {
  required int count,
  required String unit,
}) async {
  if (count <= kExportSoftLimit) return true;
  final confirmed = await AppDialog.confirm(
    context,
    title: const Text('题目较多'),
    content: Text('一次导出的$unit较多，打印预览可能变慢，建议分批导出。'),
    confirmLabel: '继续导出',
  );
  return confirmed == true;
}
