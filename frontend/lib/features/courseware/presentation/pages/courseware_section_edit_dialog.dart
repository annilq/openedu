import 'package:flutter/material.dart' show Dialog, showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../domain/models/courseware_section.dart';
import '../../domain/models/courseware_section_kind.dart';
import 'courseware_asset_picker_sheet.dart';

/// 编辑单个讲解环节（ADR-0067 §3.3）：标题 + 教师话术（提问卡）+ 按 kind 的专属内容。
///
/// - `mediaGallery`：素材项（id 引用 + 说明）的增删；
/// - `practice`：题型（qtype）调整；
/// - `interactiveScene`：场景由 AI 起草决定，此处只调标题 / 话术，重做场景走「AI 重新起草」。
///
/// 返回更新后的 [CoursewareSectionModel]；取消则回 null，调用方不落库。
Future<CoursewareSectionModel?> showCoursewareSectionEditDialog(
  BuildContext context,
  WidgetRef ref,
  CoursewareSectionModel section,
) =>
    showDialog<CoursewareSectionModel>(
      context: context,
      builder: (_) => _SectionEditDialog(section: section),
    );

class _SectionEditDialog extends ConsumerStatefulWidget {
  const _SectionEditDialog({required this.section});

  final CoursewareSectionModel section;

  @override
  ConsumerState<_SectionEditDialog> createState() => _SectionEditDialogState();
}

class _SectionEditDialogState extends ConsumerState<_SectionEditDialog> {
  late final TextEditingController _titleCtl;
  late final TextEditingController _scriptCtl;
  late final TextEditingController _qtypeCtl;
  late CoursewareSectionModel _draft;

  @override
  void initState() {
    super.initState();
    _titleCtl = TextEditingController(text: widget.section.title);
    _scriptCtl = TextEditingController(text: widget.section.script);
    _qtypeCtl = TextEditingController(
      text: (widget.section.payload['qtype'] as String?) ?? '',
    );
    _draft = widget.section;
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _scriptCtl.dispose();
    _qtypeCtl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _items {
    final raw = _draft.payload['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  Future<void> _addAsset() async {
    final updated = await showCoursewareAssetPicker(
      context,
      ref,
      current: _draft.payload,
    );
    if (updated == null) return;
    setState(() => _draft = _draft.copyWith(payload: updated));
  }

  void _removeItem(int index) {
    final items = [..._items]..removeAt(index);
    setState(
      () => _draft = _draft.copyWith(payload: {..._draft.payload, 'items': items}),
    );
  }

  void _save() {
    final payload = switch (_draft.kind) {
      CoursewareSectionKind.practice => {
          ..._draft.payload,
          'qtype': _qtypeCtl.text.trim(),
        },
      _ => _draft.payload,
    };
    final updated = _draft.copyWith(
      title: _titleCtl.text.trim(),
      script: _scriptCtl.text.trim(),
      payload: payload,
    );
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('编辑环节', style: text.titleLarge),
              const SizedBox(height: AppSpacing.md),
              AppTextField(label: '环节标题', controller: _titleCtl),
              const SizedBox(height: AppSpacing.md),
              AppTextField(label: '教师话术 / 提问卡', controller: _scriptCtl),
              const SizedBox(height: AppSpacing.md),
              if (_draft.kind == CoursewareSectionKind.mediaGallery) ...[
                Text('素材', style: text.labelMedium),
                const SizedBox(height: AppSpacing.sm),
                ..._items.asMap().entries.map((e) => _itemRow(e.key, e.value, app, text)),
                AppTextAction(label: '添加素材', onPressed: _addAsset),
              ] else if (_draft.kind == CoursewareSectionKind.practice) ...[
                AppTextField(label: '题型（qtype）', controller: _qtypeCtl),
              ] else if (_draft.isUnknownKind) ...[
                Text(
                  '未知环节类型，无法编辑内容。',
                  style: text.bodySmall?.copyWith(color: app.error),
                ),
              ],
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppTextAction(
                    label: '取消',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppPrimaryButton(label: '保存', onPressed: _save),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemRow(
    int index,
    Map<String, dynamic> item,
    AppColors app,
    AppText text,
  ) {
    final caption = item['caption'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              caption.isEmpty ? '（未命名素材）' : caption,
              style: text.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppTextAction(
            label: '移除',
            onPressed: () => _removeItem(index),
          ),
        ],
      ),
    );
  }
}
