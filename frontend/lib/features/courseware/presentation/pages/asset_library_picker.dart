import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show Colors, Dialog, showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/auth_image.dart';
import '../../domain/models/courseware_asset.dart';
import '../../providers/courseware_provider.dart';

/// 多选素材库 picker（ADR-0076）：从本人素材库挑多张，供课件环节挂载。
///
/// 复用 [coursewareAssetLibraryProvider] 列出本人全部素材，支持按文件名检索（服务端
/// 过滤）与多选上传。返回**选中的 asset id 列表**；取消回 null。
///
/// 与旧的单选 picker 不同——这里可一次勾选多张，确认后由调用方按 id 落库。
Future<List<String>?> showAssetLibraryPicker(
  BuildContext context,
  WidgetRef ref, {
  required List<String> initialSelected,
}) =>
    showDialog<List<String>>(
      context: context,
      builder: (_) => _AssetLibraryPicker(initialSelected: initialSelected),
    );

class _AssetLibraryPicker extends ConsumerStatefulWidget {
  const _AssetLibraryPicker({required this.initialSelected});

  final List<String> initialSelected;

  @override
  ConsumerState<_AssetLibraryPicker> createState() => _AssetLibraryPickerState();
}

class _AssetLibraryPickerState extends ConsumerState<_AssetLibraryPicker> {
  final Set<String> _selected = {};
  bool _uploading = false;
  String _query = '';
  final _queryCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected);
  }

  @override
  void dispose() {
    _queryCtl.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    // file_picker 13：静态方法直接返回 List<PlatformFile>（取消时为空列表，
    // 不再有 FilePickerResult 包装，也没有 allowMultiple 形参——多选是默认行为）。
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      final ids = <String>[];
      for (final f in files) {
        final bytes = await f.readAsBytes();
        final a = await repo.uploadAsset(filename: f.name, bytes: bytes);
        ids.add(a.id);
      }
      setState(() => _selected.addAll(ids));
      if (!mounted) return;
      // 刷新当前检索条件下的列表，让新传的图立即可见并自动选中。
      ref.invalidate(
        coursewareAssetLibraryProvider(
          (knowledgePointId: null, filename: _query),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '上传失败：$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toggle(String id) =>
      setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final assets = ref.watch(
      coursewareAssetLibraryProvider((knowledgePointId: null, filename: _query)),
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('选择素材', style: text.titleLarge),
                  const Spacer(),
                  Text(
                    '已选 ${_selected.length}',
                    style: text.labelMedium?.copyWith(color: app.primary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ShadButton.outline(
                onPressed: _uploading ? null : _upload,
                child: Text(
                  _uploading ? '上传中…' : '上传图片',
                  style: text.labelMedium?.copyWith(color: app.onSurface),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('asset-picker-search'),
                label: '检索',
                controller: _queryCtl,
                hintText: '按文件名检索素材库',
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: assets.when(
                  loading: () => const Center(child: AppLoading()),
                  error: (e, _) => Center(
                    child: Text(
                      '素材库加载失败：$e',
                      style:
                          text.bodyMedium?.copyWith(color: app.onSurfaceVariant),
                    ),
                  ),
                  data: (list) => list.isEmpty
                      ? Center(
                          child: Text(
                            '没有匹配的素材',
                            style: text.bodyMedium
                                ?.copyWith(color: app.onSurfaceVariant),
                          ),
                        )
                      : _grid(context, list),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.outline(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      '取消',
                      style: text.labelMedium?.copyWith(color: app.onSurface),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppPrimaryButton(
                    label: '确认（${_selected.length}）',
                    fullWidth: false,
                    onPressed: () =>
                        Navigator.pop(context, _selected.toList()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, List<CoursewareAssetModel> list) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 520 ? 3 : 2;
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
                selected: _selected.contains(a.id),
                tileWidth: tileWidth,
                onToggle: () => _toggle(a.id),
              ),
          ],
        );
      },
    );
  }
}

/// 素材选择缩略图：点击切换选中，选中态描边 + 角标。
class _Tile extends StatelessWidget {
  const _Tile({
    required this.asset,
    required this.selected,
    required this.tileWidth,
    required this.onToggle,
  });

  final CoursewareAssetModel asset;
  final bool selected;
  final double tileWidth;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return SizedBox(
      width: tileWidth,
      child: AppFocusableAction(
        semanticLabel: selected
            ? '已选素材 ${asset.name}，点击取消'
            : '选择素材 ${asset.name}',
        hoverHighlight: true,
        onTap: onToggle,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: app.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: selected ? app.primary : app.outline,
                  width: AppElevation.borderWidth,
                ),
              ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: AuthImage(url: asset.url, fit: BoxFit.cover),
                ),
            ),
            if (selected)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: app.primary,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: const Icon(
                    LucideIcons.check,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
