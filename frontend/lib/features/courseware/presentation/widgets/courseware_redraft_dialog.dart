import 'package:flutter/material.dart' show Dialog, showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../domain/models/courseware_redraft_diff.dart';
import '../../domain/models/courseware_section.dart';

/// 重起草逐段 diff 预览（ADR-0067 第二轮 T07）。
///
/// 教师逐段选择「用新版 / 留旧版 / 采用 / 忽略」后，确认回传**合并后的环节序列**；
/// 编辑器据此走 `updateSections` 写回同一课件，不新建副本。取消回 null。
Future<List<CoursewareSectionModel>?> showCoursewareRedraftDialog(
  BuildContext context,
  CoursewareRedraftDiffModel diff,
) =>
    showDialog<List<CoursewareSectionModel>>(
      context: context,
      builder: (_) => _RedraftDialog(diff: diff),
    );

class _RedraftDialog extends ConsumerStatefulWidget {
  const _RedraftDialog({required this.diff});

  final CoursewareRedraftDiffModel diff;

  @override
  ConsumerState<_RedraftDialog> createState() => _RedraftDialogState();
}

class _RedraftDialogState extends ConsumerState<_RedraftDialog> {
  // 每项默认选「采用草稿视角」：added→采用、removed→删除、modified→用新版。
  late final List<bool> _choices =
      List.filled(widget.diff.diff.length, true);

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final items = widget.diff.diff;

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('重起草预览',
                      style: text.titleLarge
                          ?.copyWith(color: app.onSurface)),
                  const SizedBox(height: AppSpacing.xs2),
                  Text(
                    '逐段选择，确认后写回本课件（不新建副本）',
                    style: text.bodySmall
                        ?.copyWith(color: app.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: app.outline),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (_, i) => _DiffRow(
                  item: items[i],
                  useNew: _choices[i],
                  onPick: (v) => setState(() => _choices[i] = v),
                ),
              ),
            ),
            Container(height: 1, color: app.outline),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppTextAction(
                    label: '取消',
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppPrimaryButton(
                    label: '应用所选',
                    fullWidth: false,
                    onPressed: () {
                      final merged = mergeRedraftChoices(widget.diff, _choices);
                      Navigator.of(context).pop(merged);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单段差异行：状态徽标 + 标题 + 新旧文案 + 二选一开关。
class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.item,
    required this.useNew,
    required this.onPick,
  });

  final CoursewareSectionDiffModel item;
  final bool useNew;
  final ValueChanged<bool> onPick;

  // 二选一的两个标签（索引 0 = 新草稿视角，1 = 当前稿视角）。
  (String, String) get _options {
    switch (item.status) {
      case CoursewareSectionDiffStatus.added:
        return ('采用', '忽略');
      case CoursewareSectionDiffStatus.removed:
        return ('删除', '保留');
      case CoursewareSectionDiffStatus.modified:
        return ('用新版', '留旧版');
      case CoursewareSectionDiffStatus.unchanged:
        return ('', '');
    }
  }

  String _snippet(CoursewareSectionModel? s) {
    if (s == null) return '';
    final seg = s.displaySegments;
    if (seg.isNotEmpty) return seg.first.text;
    return s.script;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);

    Color badgeColor = app.onSurfaceVariant;
    String badgeText = '未变';
    switch (item.status) {
      case CoursewareSectionDiffStatus.added:
        badgeColor = app.cta;
        badgeText = '新增';
      case CoursewareSectionDiffStatus.removed:
        badgeColor = app.error;
        badgeText = '待删除';
      case CoursewareSectionDiffStatus.modified:
        badgeColor = app.onSurfaceVariant;
        badgeText = '修改';
      case CoursewareSectionDiffStatus.unchanged:
        badgeColor = app.onSurfaceVariant;
        badgeText = '未变';
    }

    final title = item.drafted?.title ?? item.current?.title ?? '';

    return Container(
      decoration: BoxDecoration(
        color: app.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: app.outline,
          width: AppElevation.borderWidthHairline,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  badgeText,
                  style: text.labelSmall?.copyWith(
                    color: badgeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: text.titleSmall?.copyWith(color: app.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (item.status == CoursewareSectionDiffStatus.modified) ...[
            const SizedBox(height: AppSpacing.xs2),
            Text('旧：${_snippet(item.current)}',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
            Text('新：${_snippet(item.drafted)}',
                style: text.bodySmall?.copyWith(color: app.onSurface)),
          ] else if (item.status ==
              CoursewareSectionDiffStatus.removed) ...[
            const SizedBox(height: AppSpacing.xs2),
            Text('当前稿有、草稿未包含：${_snippet(item.current)}',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
          ] else if (item.status ==
              CoursewareSectionDiffStatus.added) ...[
            const SizedBox(height: AppSpacing.xs2),
            Text('草稿新增：${_snippet(item.drafted)}',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
          ],
          if (item.status != CoursewareSectionDiffStatus.unchanged) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _option(true, _options.$1, context),
                const SizedBox(width: AppSpacing.sm),
                _option(false, _options.$2, context),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _option(bool newSide, String label, BuildContext context) {
    final selected = useNew == newSide;
    return Expanded(
      child: selected
          ? AppPrimaryButton(
              label: label,
              fullWidth: false,
              height: AppControl.heightSmOf(context),
              onPressed: () => onPick(newSide),
            )
          : AppTextAction(
              label: label,
              onPressed: () => onPick(newSide),
            ),
    );
  }
}
