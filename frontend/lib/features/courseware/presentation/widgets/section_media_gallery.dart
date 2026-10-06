import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../domain/models/courseware_asset.dart';
import '../../domain/models/courseware_section.dart';
import '../../providers/courseware_provider.dart';

/// `media_gallery` 环节（ADR-0067 §6 切片 5）：生活素材 / 欣赏的图廊。
///
/// payload 形如 `{items: [{asset_id, caption}]}`，素材本体在 [coursewareAssetsProvider]
/// 里——环节只存 **id 引用**，不存图。因此这里必须分三种情况，它们的语义完全不同：
///
/// | 情况 | 显示 | 依据 |
/// |---|---|---|
/// | 环节里没有 item | 空态 + 上传引导 | §3.5：**不降级为示意图** |
/// | item 的 `asset_id` 在素材库里找不到 | 「素材已移除」占位 | §4.2（决策 10 允许删素材） |
/// | 命中 | 图 + caption | — |
///
/// ⚠️ 前两种不能合并：空态是「还没到那一步」，素材已移除是「曾经有、现在没了」。
/// 合并成一个「暂无图片」会让刚删过素材的教师以为自己没传过（ADR-0066 不伪造纪律）。
class SectionMediaGallery extends ConsumerWidget {
  const SectionMediaGallery({
    super.key,
    required this.section,
  });

  final CoursewareSectionModel section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = _itemsOf(section.payload);
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: LucideIcons.imagePlus,
        title: '这一环节还没有素材',
        message: '这一环节是素材展示，但还没有放进任何图片。'
            '上传图片后，它们会按你排的顺序投给学生看。',
        steps: [
          '在课件编辑页上传这一环节要用的图片',
          '给每张图配一句「要看什么」',
          '回到演示页，图片会按这里的顺序出现',
        ],
      );
    }
    // 素材库本身是异步的：item 是否「已移除」必须在素材到位后才有结论。
    final assets = ref.watch(coursewareAssetsProvider);
    return assets.when(
      loading: () => const AppLoading.skeletonInline(),
      error: (error, _) => AppError(
        message: '素材列表加载失败：$error',
        onRetry: () => ref.invalidate(coursewareAssetsProvider),
      ),
      data: (list) => _buildGrid(context, items, list),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<_GalleryItem> items,
    List<CoursewareAssetModel> assets,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 列数只按**可用宽度**取档（ADR-0045 断点令牌），不按设备形态分支：
        // 投影 1920×1080 与笔记本 1366×768 走同一套判定，只是落在不同档上。
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : AppLayout.contentWide;
        final columns = width >= AppLayout.largeMin
            ? 3
            : width >= AppLayout.compactMax
                ? 2
                : 1;
        final tileWidth =
            (width - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final item in items)
              SizedBox(
                width: tileWidth,
                child: _buildTile(context, item, assets),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTile(
    BuildContext context,
    _GalleryItem item,
    List<CoursewareAssetModel> assets,
  ) {
    final index = assets.indexWhere((a) => a.id == item.assetId);
    if (index < 0) {
      // §4.2：素材被删了（决策 10 允许删），引用它的环节显示占位，不做级联。
      return const _RemovedAssetTile();
    }
    return _GalleryTile(asset: assets[index], caption: item.caption);
  }
}

/// payload 里的一个引用（asset_id + 说明）。
///
/// 不是 widget，只是解析产物——避免把 Map 取值散进 build 里。
class _GalleryItem {
  const _GalleryItem({required this.assetId, required this.caption});

  final String assetId;
  final String caption;
}

List<_GalleryItem> _itemsOf(Map<String, dynamic> payload) {
  final raw = payload['items'];
  if (raw is! List) return const <_GalleryItem>[];
  return <_GalleryItem>[
    for (final e in raw)
      if (e is Map)
        _GalleryItem(
          assetId: e['asset_id'] as String? ?? '',
          caption: e['caption'] as String? ?? '',
        ),
  ];
}

/// 正常态：一张图 + 它的说明。
class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.asset, required this.caption});

  final CoursewareAssetModel asset;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: app.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: app.outline,
              width: AppElevation.borderWidth,
            ),
          ),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            // 工程内没有图片缓存库（pubspec 无 cached_network_image），
            // 直接用 Image.network；加载失败必须给降级，不能留一块白底。
            child: Image.network(
              asset.url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _BrokenImageTile(),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            caption,
            style: text.bodyMedium?.copyWith(color: app.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// 图片本身取不到（断网 / url 失效）：如实说明，不放占位示意图。
class _BrokenImageTile extends StatelessWidget {
  const _BrokenImageTile();

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.imageOff,
            size: AppSpacing.xl3,
            color: app.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '图片加载失败',
            style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 「素材已移除」占位（§4.2）：素材被删了，引用还留着。
///
/// 用 [AppEmptyState.inline]：它落在图廊的网格里，88 大色块会抢走相邻图片的
/// 重量；48 小色块 + 两行字才是对的重量级（`.impeccable.md` §Empty State）。
class _RemovedAssetTile extends StatelessWidget {
  const _RemovedAssetTile();

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: app.outline,
          width: AppElevation.borderWidthHairline,
        ),
      ),
      child: const AppEmptyState.inline(
        icon: LucideIcons.trash2,
        title: '素材已移除',
        message: '这张图已不在素材库里，环节还留着对它的引用。'
            '回到课件编辑页换一张图，或删掉这一项。',
      ),
    );
  }
}
