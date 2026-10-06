import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_checkbox.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../materials/domain/repositories/material_library_repository.dart';
import '../../../../materials/providers/material_library_provider.dart';
import 'material_folder_actions.dart';

/// 资料库「资料」列表的单个资料行（ADR-0055 B6 优化）。
///
/// 知识点默认**隐藏**：行尾只留一个「灯泡」图标，点击才就地展开知识点 chips。
/// 这样列表更干净，教师不必在每行都看到一长串知识点标签；需要细看时再点开。
/// 展开态用 `primary` 高亮图标 + 缩进的 chips 区，给足「已展开」的反馈。
///
/// 多选态（[selecting]）下换一副面孔：左侧出勾选框、点/敲文件名即切换选中，
/// 右侧的行内操作（向量化 / 重提取 / 移动 / 删除）**全部隐藏**——多选态下它们
/// 既是误触源，也会把勾选框挤到看不见的宽度之外。
class MaterialLibraryMaterialRow extends ConsumerStatefulWidget {
  final MaterialItemModel mat;

  /// 是否处于多选态。
  final bool selecting;

  /// 多选态下本行是否已被勾选。
  final bool selected;

  /// 多选态下切换本行勾选；非多选态不传（点文件名无响应）。
  final VoidCallback? onToggleSelected;

  const MaterialLibraryMaterialRow({
    super.key,
    required this.mat,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelected,
  });

  @override
  ConsumerState<MaterialLibraryMaterialRow> createState() =>
      _MaterialLibraryMaterialRowState();
}

class _MaterialLibraryMaterialRowState
    extends ConsumerState<MaterialLibraryMaterialRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final mat = widget.mat;
    final selecting = widget.selecting;
    final label = kIndexStateLabels[mat.indexState] ?? mat.indexState;
    final badgeColor = switch (mat.indexState) {
      'ready' => app.primary,
      'failed' => app.error,
      'stale' => app.secondary,
      _ => app.onSurfaceVariant,
    };
    final meta = [
      if (mat.subject != null) mat.subject!,
      if (mat.grade != null) '${mat.grade}年级',
    ].join(' · ');
    final hasKp = mat.knowledgePoints.isNotEmpty;
    // 标题 + 元信息（学科 · 年级）一块 RichText，两种共用。
    final title = Text.rich(TextSpan(children: [
      TextSpan(text: mat.name),
      if (meta.isNotEmpty)
        TextSpan(
          text: '　$meta',
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
        ),
    ]));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (selecting) ...[
              AppCheckbox(
                selected: widget.selected,
                semanticLabel: widget.selected
                    ? '取消选择 ${mat.name}'
                    : '选择 ${mat.name}',
                onTap: widget.onToggleSelected,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            const Icon(LucideIcons.fileText, size: 18),
            const SizedBox(width: AppSpacing.sm),
            // 多选态下整块标题就是勾选热区（比 20px 的框好按得多）。
            if (selecting)
              Expanded(
                child: AppFocusableAction(
                  hoverHighlight: true,
                  semanticLabel: widget.selected
                      ? '取消选择 ${mat.name}'
                      : '选择 ${mat.name}',
                  onTap: widget.onToggleSelected,
                  child: title,
                ),
              )
            else
              Expanded(child: title),
            // 以下行内操作在非多选态才出现：多选态已经另有「删除选中」，留着它
            // 们只会让一行塞不下、并且和勾选框抢点击目标。
            if (!selecting) ...[
              // 知识点入口：仅在确有知识点时出现；点击就地展开/收起（不占默认空间）。
              if (hasKp)
                AppIconAction(
                  icon: LucideIcons.lightbulb,
                  iconSize: 17,
                  color: _expanded ? app.primary : null,
                  semanticLabel: _expanded ? '收起知识点' : '查看知识点',
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              Text(label,
                  style: text.bodySmall
                      ?.copyWith(color: badgeColor, fontWeight: FontWeight.w700)),
              const SizedBox(width: AppSpacing.sm),
              AppTextAction(
                label: mat.indexState == 'ready' ? '重新向量化' : '向量化',
                onPressed: () => ref
                    .read(materialLibraryNotifierProvider.notifier)
                    .vectorize(mat.id),
              ),
              AppTextAction(
                label: '重提取',
                onPressed: () => ref
                    .read(materialLibraryNotifierProvider.notifier)
                    .reextract(mat.id),
              ),
              AppTextAction(
                label: '移动',
                onPressed: () => moveMaterialToFolder(context, ref, mat),
              ),
              AppIconAction(
                icon: LucideIcons.trash2,
                iconSize: 16,
                semanticLabel: '删除资料 ${mat.name}',
                onPressed: () => ref
                    .read(materialLibraryNotifierProvider.notifier)
                    .deleteMaterial(mat.id),
              ),
            ],
          ],
        ),
        // 展开的知识点区：缩进到文件名下方，Wrap 排布 chips（沿用 AppTags.normal）。
        if (hasKp && _expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: 26,
              top: AppSpacing.xs,
              bottom: AppSpacing.xs,
            ),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final kp in mat.knowledgePoints) AppTags.normal(kp),
              ],
            ),
          ),
      ],
    );
  }
}
