import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/app_image_viewer.dart';
import '../../../../shared/widgets/auth_image.dart';
import '../../domain/models/courseware_asset.dart';
import '../../providers/courseware_provider.dart';

/// 素材库页（ADR-0077）：教师自传图片的集中管理入口。
///
/// 与旧的「平台预置 CC0 包」彻底分离——这里只收录教师自己上传的图片（单一来源，
/// 无平台兜底）。能力刻意做薄：多选上传、grid 陈列、点缩略图放大看原图、逐张删除。
/// 课件环节里「添加素材」复用的 [showAssetLibraryPicker] 与这里共用同一份
/// [coursewareAssetLibraryProvider]，数据始终一致。
class AssetLibraryScreen extends ConsumerStatefulWidget {
  const AssetLibraryScreen({super.key});

  @override
  ConsumerState<AssetLibraryScreen> createState() => _AssetLibraryScreenState();
}

class _AssetLibraryScreenState extends ConsumerState<AssetLibraryScreen> {
  bool _uploading = false;
  String _query = '';
  final _queryCtl = TextEditingController();
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void dispose() {
    _queryCtl.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    // file_picker 13：直接返回 List<PlatformFile>（取消时为空列表，无 allowMultiple
    // 形参，多选是默认行为）。
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      for (final f in files) {
        final bytes = await f.readAsBytes();
        await repo.uploadAsset(filename: f.name, bytes: bytes);
      }
      if (!mounted) return;
      // 刷新当前检索条件下的列表，让新传的图立即可见。
      ref.invalidate(
        coursewareAssetLibraryProvider((knowledgePointId: null, filename: _query)),
      );
      AppToast.show(context, '已上传 ${files.length} 张素材');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '上传失败：$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(CoursewareAssetModel asset) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: const Text('删除素材'),
      content: Text('确定删除「${asset.name}」？引用它的课件环节会显示'
          '「素材已移除」占位，不会被级联删除。'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(coursewareRepositoryProvider).deleteAsset(asset.id);
      if (!mounted) return;
      ref.invalidate(
        coursewareAssetLibraryProvider((knowledgePointId: null, filename: _query)),
      );
      AppToast.show(context, '已删除 ${asset.name}');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '删除失败：$e');
    }
  }

  void _open(CoursewareAssetModel asset) =>
      showImageViewer(context, url: asset.url, name: asset.name);

  void _enterSelect() => setState(() {
        _selecting = true;
        _selected.clear();
      });

  void _exitSelect() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _toggleSelect(String id) => setState(() {
        if (_selected.contains(id)) {
          _selected.remove(id);
        } else {
          _selected.add(id);
        }
      });

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final confirmed = await AppDialog.confirm(
      context,
      title: const Text('删除选中素材'),
      content: Text('确定删除选中的 ${ids.length} 张素材？引用它们的课件环节会显示'
          '「素材已移除」占位，不会被级联删除。'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      for (final id in ids) {
        await repo.deleteAsset(id);
      }
      if (!mounted) return;
      setState(() {
        _selecting = false;
        _selected.clear();
      });
      ref.invalidate(
        coursewareAssetLibraryProvider((knowledgePointId: null, filename: _query)),
      );
      AppToast.show(context, '已删除 ${ids.length} 张素材');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final assets = ref.watch(
      coursewareAssetLibraryProvider((knowledgePointId: null, filename: _query)),
    );
    // 有素材且非加载态才允许进入选择。
    final canSelect = assets.maybeWhen(
      data: (l) => l.isNotEmpty,
      orElse: () => false,
    );
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 页头：标题 + 说明，给页面明确的入口身份与留白。
          Text(
            '素材库',
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '只收录你自己上传的图片，用于课件素材。支持多选上传、点击缩略图放大查看原图。',
            style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 工具条：普通态 = 上传 + 检索 + 进入选择；选择态 = 取消 + 批量删除。
          if (_selecting)
            Row(
              children: [
                AppTextAction(label: '取消', onPressed: _exitSelect),
                const SizedBox(width: AppSpacing.sm),
                AppPrimaryButton(
                  label: '删除选中(${_selected.length})',
                  fullWidth: false,
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                ),
              ],
            )
          else
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppPrimaryButton(
                  label: _uploading ? '上传中…' : '上传图片',
                  onPressed: _uploading ? null : _upload,
                ),
                AppTextAction(
                  label: '选择',
                  onPressed: canSelect ? _enterSelect : null,
                ),
                SizedBox(
                  width: 320,
                  child: AppTextField(
                    key: const Key('asset-library-search'),
                    label: '检索',
                    controller: _queryCtl,
                    hintText: '按文件名检索素材库',
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: assets.when(
              loading: () =>
                  const Center(child: AppLoading.skeletonInline()),
              error: (e, _) => Center(
                child: AppEmptyState(
                  icon: LucideIcons.imageOff,
                  title: '素材库加载失败',
                  message: '$e',
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: AppEmptyState(
                      icon: LucideIcons.imagePlus,
                      title: _query.isEmpty ? '素材库还是空的' : '没有匹配的素材',
                      message: _query.isEmpty
                          ? '点上方「上传图片」，从本地挑一张图传上来。'
                              '素材只收录你自己上传的图片，不做任何平台预置。'
                          : '换个关键词，或清空检索看看全部素材。',
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final columns = width >= AppLayout.largeMin
                        ? 4
                        : width >= AppLayout.compactMax
                            ? 3
                            : width >= 420
                                ? 2
                                : 1;
                    final tileWidth =
                        (width - AppSpacing.md * (columns - 1)) / columns;
                    return GridView.count(
                      crossAxisCount: columns,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childAspectRatio: 4 / 3,
                      children: [
                        for (final a in list)
                          _Tile(
                            asset: a,
                            tileWidth: tileWidth,
                            selecting: _selecting,
                            selected: _selected.contains(a.id),
                            onOpen: () => _open(a),
                            onDelete: () => _delete(a),
                            onToggle: () => _toggleSelect(a.id),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 素材库缩略图。
///
/// - 普通态：点击放大看原图，右上角删除（trash2）。
/// - 选择态：点击切换选中，右上角显示 check（已选）/ circle（未选）标识，
///   选中时卡片描边转为品牌色（与课件环节列表的选择交互一致，ADR-0077）。
class _Tile extends StatelessWidget {
  const _Tile({
    required this.asset,
    required this.tileWidth,
    this.selecting = false,
    this.selected = false,
    required this.onOpen,
    required this.onDelete,
    required this.onToggle,
  });

  final CoursewareAssetModel asset;
  final double tileWidth;
  final bool selecting;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final borderColor = selected ? app.primary : app.outline;
    final borderWidth =
        selected ? AppElevation.borderWidth * 2 : AppElevation.borderWidth;
    return SizedBox(
      width: tileWidth,
      child: Stack(
        children: [
          AppFocusableAction(
            semanticLabel: selecting
                ? (selected ? '已选素材 ${asset.name}，点按取消' : '选择素材 ${asset.name}')
                : '放大查看 ${asset.name}',
            hoverHighlight: true,
            onTap: selecting ? onToggle : onOpen,
            child: Container(
              width: tileWidth,
              decoration: BoxDecoration(
                color: app.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: borderColor, width: borderWidth),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: AuthImage(url: asset.url, fit: BoxFit.cover),
              ),
            ),
          ),
          // 文件名为空时仍给一个可读占位，避免卡片无标题。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: const Color(0xE6000000),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(AppRadius.card),
                ),
              ),
              child: Text(
                asset.name.isEmpty ? '未命名素材' : asset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.textOf(context)
                    .labelSmall
                    ?.copyWith(color: const Color(0xFFFFFFFF)),
              ),
            ),
          ),
          // 右上角：选择态显示选框标识（check/circle），普通态显示删除。
          Positioned(
            top: 4,
            right: 4,
            child: selecting
                ? Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: selected ? app.primary : app.surface,
                      shape: BoxShape.circle,
                      border: selected
                          ? null
                          : Border.all(color: app.outline, width: 1),
                    ),
                    child: Icon(
                      selected ? LucideIcons.check : LucideIcons.circle,
                      size: 16,
                      color: selected
                          ? const Color(0xFFFFFFFF)
                          : app.onSurfaceVariant,
                    ),
                  )
                : AppIconAction(
                    icon: LucideIcons.trash2,
                    iconSize: 16,
                    semanticLabel: '删除 ${asset.name}',
                    onPressed: onDelete,
                  ),
          ),
        ],
      ),
    );
  }
}
