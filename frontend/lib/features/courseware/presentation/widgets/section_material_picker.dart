import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_image_viewer.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/auth_image.dart';
import '../../domain/models/courseware_asset.dart';
import '../../domain/models/courseware_section.dart';
import '../../providers/courseware_provider.dart';
import '../pages/asset_library_picker.dart';

/// 环节「关联素材」区（ADR-0076，内容块统一化）：任意 kind 的环节都能挂素材。
///
/// 从环节编辑弹窗里整块抽出来（ADR-0058 §2：Page → Section → Widget，一个文件只
/// 暴露一个公开物）——它自带「素材从哪来」（素材库 picker）与「素材列表怎么解析」
/// （`coursewareAssetsProvider` 把 id 换成图）两件事，弹窗只需要知道**当前挂了哪些**
/// 并在变化时收到 [onChanged]。
///
/// 素材被删后引用仍在时显示「素材已移除」占位：不级联删除，引用保留——教师可能只是
/// 误删，静默丢引用会让环节内容无声消失。
class SectionMaterialPicker extends ConsumerStatefulWidget {
  const SectionMaterialPicker({
    super.key,
    required this.materials,
    required this.onChanged,
  });

  final List<CoursewareMaterialItem> materials;

  /// 整列覆盖写（与后端 `updateSections` 的整列覆盖语义一致）。
  final ValueChanged<List<CoursewareMaterialItem>> onChanged;

  @override
  ConsumerState<SectionMaterialPicker> createState() =>
      _SectionMaterialPickerState();
}

class _SectionMaterialPickerState
    extends ConsumerState<SectionMaterialPicker> {
  Future<void> _addAsset() async {
    final selectedIds = await showAssetLibraryPicker(
      context,
      ref,
      initialSelected: widget.materials.map((m) => m.assetId).toList(),
    );
    if (selectedIds == null) return;
    final captionById = {
      for (final m in widget.materials) m.assetId: m.caption,
    };
    widget.onChanged(<CoursewareMaterialItem>[
      for (final id in selectedIds)
        CoursewareMaterialItem(
          assetId: id,
          caption: captionById[id] ?? '',
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('关联素材', style: text.labelMedium),
            const Spacer(),
            AppPrimaryButton(
              label: '添加素材',
              fullWidth: false,
              onPressed: _addAsset,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _grid(),
      ],
    );
  }

  Widget _grid() {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    if (widget.materials.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text('还没有关联素材，点上方「添加素材」从素材库挑图。',
            style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
      );
    }
    final assets = ref.watch(coursewareAssetsProvider);
    return assets.when(
      loading: () => const Center(child: AppLoading.skeletonInline()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text('素材列表加载失败：$e',
            style: text.bodySmall?.copyWith(color: app.error)),
      ),
      data: (list) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 4 / 3,
        children: [
          for (final m in widget.materials)
            _MaterialTile(
              item: m,
              asset: list.where((a) => a.id == m.assetId).firstOrNull,
              onOpen: () {
                final a = list.where((x) => x.id == m.assetId).firstOrNull;
                if (a != null) showImageViewer(context, url: a.url, name: a.name);
              },
              onRemove: () => widget.onChanged(
                widget.materials.where((x) => x.assetId != m.assetId).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

/// 素材缩略图：点图放大看原图，右上角删除；找不到对应素材时显示「素材已移除」占位。
class _MaterialTile extends StatelessWidget {
  const _MaterialTile({
    required this.item,
    required this.asset,
    required this.onOpen,
    required this.onRemove,
  });

  final CoursewareMaterialItem item;
  final CoursewareAssetModel? asset;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final caption = item.caption;
    return Stack(
      children: [
        AppFocusableAction(
          semanticLabel:
              asset != null ? '放大查看 ${asset!.name}' : '素材已移除',
          hoverHighlight: true,
          onTap: asset != null ? onOpen : null,
          child: Container(
            decoration: BoxDecoration(
              color: app.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: app.outline,
                width: AppElevation.borderWidth,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: asset != null
                  ? AuthImage(url: asset!.url, fit: BoxFit.cover)
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.trash2, size: 20),
                            SizedBox(height: AppSpacing.xs),
                            Text('素材已移除', textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
        if (caption.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: const Color(0xE6000000),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(AppRadius.card),
                ),
              ),
              child: Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall
                    ?.copyWith(color: const Color(0xFFFFFFFF)),
              ),
            ),
          ),
        Positioned(
          top: 2,
          right: 2,
          child: AppIconAction(
            icon: LucideIcons.trash2,
            iconSize: 15,
            semanticLabel: '移除该素材',
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}
