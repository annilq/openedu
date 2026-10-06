import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../../shared/theme/app_theme.dart';

/// 知识点目录的来源说明条。
///
/// **为什么需要它**：知识点只来自已上传的教材（ADR-0066），所以「某个范围一条知识
/// 点都没有」是家常便饭——下拉空着的时候，教师需要知道是**没传教材**还是**传了但没
/// 识别出知识点**，这两件事的下一步完全不同（去上传 / 去重新提取）。
///
/// 后端把这句话放在 `KnowledgePointDirectory.notice` 里，这里原样摆出来。空列表本身
/// 不传达这个区别，没有它教师就只能自己猜。
class DirectoryNoticeBar extends StatelessWidget {
  final String text;

  const DirectoryNoticeBar({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text_ = AppTheme.textOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        // 信息提示用弱一档的描边色（secondary），区别于错误（error）与中性骨架条。
        color: app.secondary.withValues(alpha: 0.08),
        border: Border.all(color: app.secondary, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: app.secondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: text_.bodySmall?.copyWith(color: app.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
