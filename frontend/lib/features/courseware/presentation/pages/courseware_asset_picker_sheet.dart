import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show Dialog, showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../domain/models/courseware_asset.dart';
import '../../providers/courseware_provider.dart';

/// 为 `media_gallery` 环节选素材的弹窗（ADR-0067 §3.5）。两种来源：
///
/// - **从已有素材库挑**：[coursewareAssetsProvider] 列出本教师全部素材；
/// - **上传新图片**：[FilePicker] 取字节 → [CoursewareRepository.uploadAsset]。
///
/// 返回**更新后的 payload**（含 items 列表）；取消则回 null，调用方沿用原 payload。
Future<Map<String, dynamic>?> showCoursewareAssetPicker(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> current,
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AssetPickerSheet(current: current),
    );

class _AssetPickerSheet extends ConsumerStatefulWidget {
  const _AssetPickerSheet({required this.current});

  final Map<String, dynamic> current;

  @override
  ConsumerState<_AssetPickerSheet> createState() => _AssetPickerSheetState();
}

class _AssetPickerSheetState extends ConsumerState<_AssetPickerSheet> {
  bool _uploading = false;

  List<Map<String, dynamic>> get _items {
    final raw = widget.current['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    final file = files.first;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final repo = ref.read(coursewareRepositoryProvider);
      final asset = await repo.uploadAsset(
        filename: file.name,
        bytes: bytes,
      );
      final items = [
        ..._items,
        {'asset_id': asset.id, 'caption': asset.name},
      ];
      if (!mounted) return;
      Navigator.pop(context, {...widget.current, 'items': items});
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '上传失败：$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _pick(CoursewareAssetModel a) {
    final items = [
      ..._items,
      {'asset_id': a.id, 'caption': a.name},
    ];
    Navigator.pop(context, {...widget.current, 'items': items});
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final assets = ref.watch(coursewareAssetsProvider);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择素材', style: text.titleLarge),
              const SizedBox(height: AppSpacing.md),
              AppTextAction(
                label: _uploading ? '上传中…' : '上传新图片',
                onPressed: _uploading ? null : _upload,
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: assets.when(
                  loading: () => const Center(child: AppLoading()),
                  error: (e, _) =>
                      Center(child: Text('素材库加载失败：$e')),
                  data: (list) => ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final a = list[i];
                      return AppFocusableAction(
                        semanticLabel: '选择素材 ${a.name}',
                        hoverHighlight: true,
                        onTap: () => _pick(a),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                  child: Image.network(
                                    a.url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(LucideIcons.imageOff),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(
                                  a.name,
                                  style: text.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppTextAction(
                    label: '完成',
                    onPressed: () =>
                        Navigator.pop(context, widget.current),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
