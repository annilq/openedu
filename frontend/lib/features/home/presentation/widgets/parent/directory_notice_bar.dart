import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../../shared/theme/app_theme.dart';

/// 知识点目录来源说明条（ADR-0061 §L）。
///
/// **为什么需要它**：知识点目录的「骨架兜底」是分不出学期的大颗粒冷启动目录
/// （见后端 `skeleton_names(subject, grade)`，不吃学期参数）。当某个范围还没有
/// 资料涌现的真实知识点时，切学期拿到的下拉会**逐字相同**——家长据此会以为
/// 「知识点不随学期联动」，其实只是那个学期还没上传资料。
///
/// 所以把后端给的 `notice` 原样摆出来：把「联动坏了」与「这个范围还没数据」
/// 两种情形区分开，避免前者被当成后者报障。
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
