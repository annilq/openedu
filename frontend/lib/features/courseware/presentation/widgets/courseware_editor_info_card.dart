import 'package:flutter/widgets.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../domain/models/courseware.dart';

/// 课件信息卡片（courseware-round-3 T02）：标题 / 范围 / 状态 / 教学目标，
/// 右上角「编辑」打开信息编辑弹窗（复用已有 `PATCH /{id}`）。
///
/// 从编辑器页整块抽出来（ADR-0058 §2：Page → Section → Widget）——它只读一份
/// [CoursewareModel]、只回传一次「点编辑」，页里没有第二处需要它的地方。
class CoursewareEditorInfoCard extends StatelessWidget {
  const CoursewareEditorInfoCard({
    super.key,
    required this.courseware,
    this.onEdit,
  });

  final CoursewareModel courseware;

  /// 传 null = 当前不可编辑（如正在处理中），按钮自动禁用。
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final cw = courseware;
    final scope = [
      if (cw.subject != null && cw.subject!.isNotEmpty) cw.subject!,
      if (cw.grade != null) '${cw.grade}年级',
      if (cw.semester != null && cw.semester!.isNotEmpty) cw.semester!,
    ].join(' · ');
    final scopeLabel = scope.isEmpty ? cw.kpName : '$scope · ${cw.kpName}';
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surfaceRaised,
        border: Border.all(color: app.outline, width: AppElevation.borderWidth),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  cw.displayTitle,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              AppTextAction(label: '编辑', onPressed: onEdit),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(scopeLabel,
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: cw.isReady ? app.primaryContainer : app.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  cw.isReady ? '可上讲台' : '草稿',
                  style: text.labelSmall?.copyWith(
                    color: cw.isReady ? app.onPrimaryContainer : app.onSurfaceVariant,
                  ),
                ),
              ),
              if (cw.objective != null && cw.objective!.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '目标：${cw.objective}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall
                        ?.copyWith(color: app.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
