import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:shadcn_ui/shadcn_ui.dart' show ShadCheckbox;

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/utils/question_labels.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import 'bank_question_detail.dart';

/// 题库列表的一行（ADR-0061 §S）。
///
/// **整卡 onTap 是「多选」**（批量归档/删除/导出），不是详情 —— 所以详情走行内
/// 显式入口「查看详情」。别把 onTap 改成打开详情：那会让家长没法多选题。
///
/// 从 `ParentQuestionBankView` 拆出来的原因：ADR-0058 的行数棘轮（该视图已超限，
/// 且基线只许下调）。回调全部构造注入，本文件不依赖视图的私有状态。
class BankQuestionRow extends StatelessWidget {
  final BankQuestionItem item;
  final bool selected;

  /// 整卡点击 = 切换选中（批量操作）。
  final VoidCallback onToggle;

  /// 「用过 N 次」标签点击 = 看引用任务（闭环「用过 → 在哪里用」）。
  final VoidCallback onShowUsages;

  const BankQuestionRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onToggle,
    required this.onShowUsages,
  });

  @override
  Widget build(BuildContext context) {
    final q = item;
    final app = AppTheme.colorsOf(context);
    final selected = this.selected;
    return AppCard.listRow(
      // 列表行变体：1px 墨黑描边、无阴影（ADR-0044「列表降噪」）。
      // 选中态描边转为 primary，复用 [AppCard.border] 透传。
      // 行距由 AppCardList 统一给，卡片自身零外边距。
      margin: EdgeInsets.zero,
      border: Border.all(
        color: selected ? app.primary : AppBrutal.ink,
        width: 1,
      ),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.stem,
                    style: AppTheme.textOf(context)
                        .bodyLarge
                        ?.copyWith(height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _tag(context, app, q.subject),
                      _tag(context, app, '${q.grade}年级'),
                      _tag(context, app, q.knowledgePoint),
                      _tag(context, app, qtypeLabelFull(q.qtype)),
                      // 已归档的行必须自己说出来：在「含已归档」视图里，
                      // 归档题与在用题长得一样，看不出区别。
                      if (q.archivedAt != null) _tag(context, app, '已归档'),
                      if (q.usageCount > 0) _usageTag(context, app, q),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // 详情含题干全文 + 选项 + 答案 + 解析 + 知识点信息 + 交互讲解
                  //（ADR-0061 §S）。**不劫持整卡 onTap** —— 那是「多选」，
                  // 家长要靠它批量归档/删除/导出；详情走行内显式入口。
                  AppTextAction(
                    label: '查看详情',
                    onPressed: () => BankQuestionDetail.show(context, q),
                  ),
                ],
              ),
            ),
            ShadCheckbox(
              value: selected,
              onChanged: (_) => onToggle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, AppColors app, String text,
      {Color? tone}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: app.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: AppTheme.textOf(context).labelSmall?.copyWith(
              color: tone ?? app.onSurfaceVariant,
            ),
      ),
    );
  }

  /// 「用过 N 次」标签：可点击，弹出引用任务列表（闭环「用过 → 在哪里用」）。
  ///
  /// 走 [AppFocusableAction] 而非裸 `GestureDetector`——后者不进焦点树
  /// （ADR-0046）。焦点环圆角跟随标签自身的 [AppRadius.sm]。
  Widget _usageTag(BuildContext context, AppColors app, BankQuestionItem q) {
    return AppFocusableAction(
      onTap: onShowUsages,
      hoverHighlight: true,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      semanticLabel: '查看引用过 ${q.usageCount} 次的任务',
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: app.secondaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.link, size: 12, color: app.onSecondaryContainer),
            const SizedBox(width: 4),
            Text(
              '用过 ${q.usageCount} 次',
              style: AppTheme.textOf(context).labelSmall?.copyWith(
                    color: app.onSecondaryContainer,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
