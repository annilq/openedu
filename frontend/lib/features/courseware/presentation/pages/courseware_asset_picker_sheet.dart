import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show Dialog, showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../domain/models/courseware_asset.dart';
import '../../providers/courseware_provider.dart';

/// 为 `media_gallery` 环节选素材的弹窗（ADR-0067 §3.5）。两种来源：
///
/// - **从素材库挑**：[coursewareAssetLibraryProvider] 列出本教师全部素材，可按文件名
///   检索（T04 素材库检索端点）；
/// - **上传新图片**：[FilePicker] 取字节 → [CoursewareRepository.uploadAsset]。
///
/// 返回**更新后的 payload**（含 items 列表）；取消则回 null，调用方沿用原 payload。
Future<Map<String, dynamic>?> showCoursewareAssetPicker(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> current,
  String? knowledgePointId,
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AssetPickerSheet(
        current: current,
        knowledgePointId: knowledgePointId,
      ),
    );

class _AssetPickerSheet extends ConsumerStatefulWidget {
  const _AssetPickerSheet({
    required this.current,
    this.knowledgePointId,
  });

  final Map<String, dynamic> current;
  final String? knowledgePointId;

  @override
  ConsumerState<_AssetPickerSheet> createState() => _AssetPickerSheetState();
}

class _AssetPickerSheetState extends ConsumerState<_AssetPickerSheet> {
  bool _uploading = false;
  String _query = '';
  final _queryCtl = TextEditingController();

  List<Map<String, dynamic>> get _items {
    final raw = widget.current['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  @override
  void dispose() {
    _queryCtl.dispose();
    super.dispose();
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
    final app = AppTheme.colorsOf(context);
    final assets = ref.watch(
      coursewareAssetLibraryProvider(
        (knowledgePointId: widget.knowledgePointId, filename: _query),
      ),
    );
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
              // T04：素材库文件名检索框（服务端按 filename 过滤）
              AppTextField(
                key: const Key('asset-search'),
                label: '素材库检索',
                controller: _queryCtl,
                hintText: '按文件名检索素材库',
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: assets.when(
                  loading: () => const Center(child: AppLoading()),
                  error: (e, _) =>
                      Center(child: Text('素材库加载失败：$e')),
                  data: (list) => list.isEmpty
                      ? const Center(child: Text('没有匹配的素材'))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final a = list[i];
                            return AppFocusableAction(
                              semanticLabel: '选择素材 ${a.name}',
                              hoverHighlight: true,
                              onTap: () => _pick(a),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.sm),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 40,
                                          height: 40,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                                AppRadius.sm),
                                            child: Image.network(
                                              a.url,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(
                                                      LucideIcons.imageOff),
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
                                        if (a.isPlatformCc0)
                                          _cc0Badge(context),
                                      ],
                                    ),
                                    if (a.isPlatformCc0) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        '许可：${a.license}　来源：${a.sourceUrl}',
                                        style: text.bodySmall?.copyWith(
                                          color: app.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
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
                    onPressed: () => Navigator.pop(context, widget.current),
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

/// CC0 公共素材角标（T08 / ADR-0067 §3.5·§5）：与自有素材并列展示时的可见来源标记。
Widget _cc0Badge(BuildContext context) {
  final app = AppTheme.colorsOf(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
    decoration: BoxDecoration(
      color: app.cta.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      'CC0',
      style: AppTheme.textOf(context)
          .labelSmall
          ?.copyWith(color: app.cta, fontWeight: FontWeight.w700),
    ),
  );
}
