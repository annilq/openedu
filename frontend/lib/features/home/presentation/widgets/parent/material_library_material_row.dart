import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../materials/domain/repositories/material_library_repository.dart';
import '../../../../materials/providers/material_library_provider.dart';
import 'material_folder_actions.dart';

/// 资料库「资料」列表的单个资料行（ADR-0055 B6 优化）。
///
/// 知识点默认**隐藏**：行尾只留一个「灯泡」图标，点击才就地展开知识点 chips。
/// 这样列表更干净，家长不必在每行都看到一长串知识点标签；需要细看时再点开。
/// 展开态用 `primary` 高亮图标 + 缩进的 chips 区，给足「已展开」的反馈。
class MaterialLibraryMaterialRow extends ConsumerStatefulWidget {
  final MaterialItemModel mat;

  const MaterialLibraryMaterialRow({super.key, required this.mat});

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.fileText, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: mat.name),
                if (meta.isNotEmpty)
                  TextSpan(
                    text: '　$meta',
                    style: text.bodySmall
                        ?.copyWith(color: app.onSurfaceVariant),
                  ),
              ])),
            ),
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
