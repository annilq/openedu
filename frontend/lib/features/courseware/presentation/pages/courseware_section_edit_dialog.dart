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

/// 编辑单个讲解环节（ADR-0067 §3.3）：标题 + 教师话术（提问卡，可多段 + 重点）+ 按 kind 的专属内容。
///
/// - 话术（T02）：从单文本框升级为有序段列表，每段可切重点（普通 / 加粗 / 高亮）；
///   旧单串话术打开时自动包成一段，升级后整体覆盖写 `script_segments`，旧 `script` 同步压平。
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
  late final TextEditingController _qtypeCtl;
  late List<TextEditingController> _segCtls;
  late List<CoursewareScriptEmphasis> _segEmphasis;
  late CoursewareSectionModel _draft;

  @override
  void initState() {
    super.initState();
    _titleCtl = TextEditingController(text: widget.section.title);
    _qtypeCtl = TextEditingController(
      text: (widget.section.payload['qtype'] as String?) ?? '',
    );

    // 旧单串话术 → 包成一段；否则沿用既有段列表；两者皆空给一段空的便于直接输入。
    final seed = widget.section.scriptSegments.isNotEmpty
        ? widget.section.scriptSegments
        : (widget.section.script.isNotEmpty
            ? [CoursewareScriptSegment(text: widget.section.script)]
            : const [CoursewareScriptSegment()]);
    _segCtls = [for (final s in seed) TextEditingController(text: s.text)];
    _segEmphasis = [for (final s in seed) s.emphasis];

    _draft = widget.section;
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _qtypeCtl.dispose();
    for (final c in _segCtls) {
      c.dispose();
    }
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

  void _addSegment() => setState(() {
        _segCtls.add(TextEditingController());
        _segEmphasis.add(CoursewareScriptEmphasis.none);
      });

  void _removeSegment(int index) => setState(() {
        _segCtls[index].dispose();
        _segCtls.removeAt(index);
        _segEmphasis.removeAt(index);
      });

  void _cycleEmphasis(int index) => setState(() {
        _segEmphasis[index] = switch (_segEmphasis[index]) {
          CoursewareScriptEmphasis.none => CoursewareScriptEmphasis.bold,
          CoursewareScriptEmphasis.bold => CoursewareScriptEmphasis.highlight,
          CoursewareScriptEmphasis.highlight => CoursewareScriptEmphasis.none,
        };
      });

  String _emphasisLabel(CoursewareScriptEmphasis e) => switch (e) {
        CoursewareScriptEmphasis.none => '普通',
        CoursewareScriptEmphasis.bold => '加粗',
        CoursewareScriptEmphasis.highlight => '高亮',
      };

  void _save() {
    final payload = switch (_draft.kind) {
      CoursewareSectionKind.practice => {
          ..._draft.payload,
          'qtype': _qtypeCtl.text.trim(),
        },
      _ => _draft.payload,
    };
    final segs = <CoursewareScriptSegment>[];
    for (var i = 0; i < _segCtls.length; i++) {
      final t = _segCtls[i].text.trim();
      if (t.isEmpty) continue;
      segs.add(CoursewareScriptSegment(text: t, emphasis: _segEmphasis[i]));
    }
    final updated = _draft.copyWith(
      title: _titleCtl.text.trim(),
      // 旧单串 script 同步压平成多段文本，保证任何仍读 script 的消费者不丢内容。
      script: segs.map((s) => s.text).join('\n'),
      scriptSegments: segs,
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
              Text('教师话术 / 提问卡（可分多段，每段可标重点）',
                  style: text.labelSmall),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _segCtls.length; i++)
                        _segmentRow(i, app, text),
                      AppTextAction(label: '添加一段', onPressed: _addSegment),
                      const SizedBox(height: AppSpacing.md),
                      if (_draft.kind == CoursewareSectionKind.mediaGallery) ...[
                        Text('素材', style: text.labelMedium),
                        const SizedBox(height: AppSpacing.sm),
                        ..._items.asMap().entries.map(
                              (e) => _itemRow(e.key, e.value, app, text),
                            ),
                        AppTextAction(label: '添加素材', onPressed: _addAsset),
                      ] else if (_draft.kind == CoursewareSectionKind.practice) ...[
                        AppTextField(label: '题型（qtype）', controller: _qtypeCtl),
                      ] else if (_draft.isUnknownKind) ...[
                        Text(
                          '未知环节类型，无法编辑内容。',
                          style: text.bodySmall?.copyWith(color: app.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppTextAction(
                    label: '取消',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppPrimaryButton(
                    label: '保存',
                    fullWidth: false,
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segmentRow(int index, AppColors app, AppText text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppTextField(
              label: '第 ${index + 1} 段',
              controller: _segCtls[index],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppTextAction(
            label: _emphasisLabel(_segEmphasis[index]),
            onPressed: () => _cycleEmphasis(index),
          ),
          AppTextAction(
            label: '移除',
            onPressed:
                _segCtls.length > 1 ? () => _removeSegment(index) : null,
          ),
        ],
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
