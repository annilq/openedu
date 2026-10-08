import 'package:flutter/material.dart' show Dialog, showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../domain/models/courseware_section.dart';
import '../../providers/courseware_provider.dart';
import 'courseware_asset_picker_sheet.dart';
import 'section_scene_association_block.dart';

/// 编辑单个讲解环节（ADR-0067 §3.3，内容块统一化）：
///
/// **每个环节都是同一张 CMS 式表单**，与 [CoursewareSectionModel.kind] 无关——
/// 标题 + 教师话术（提问卡，可多段 + 重点）+ **关联素材** + **关联知识点场景**。
/// 任何 kind 的环节都能挂素材与场景；旧 AI 起草数据（[payload] 内嵌 items / 整份
/// SceneSpec）在打开编辑时归一化到顶层 [CoursewareSectionModel.materials] /
/// [CoursewareSectionModel.scene]（见 [resolvedMaterials] / [resolvedScene]），保存时
/// 不再写 legacy [payload]，让统一表单只操作顶层字段。
///
/// - 话术（T02）：从单文本框升级为有序段列表，每段可切重点（普通 / 加粗 / 高亮）；
///   旧单串话术打开时自动包成一段，升级后整体覆盖写 `script_segments`，旧 `script` 同步压平。
/// - 关联素材：复用素材库 picker，结果写进顶层 `materials`（id 引用 + 说明）。
/// - 关联知识点场景：按知识点拉取其已配置的讲解模板（ADR-0061 SceneSpec）供复用，
///   选中即快照式复制进本环节顶层 `scene`（不随知识点后续改动自动更新）。
///
/// 返回更新后的 [CoursewareSectionModel]；取消则回 null，调用方不落库。
///
/// [knowledgePointId] / [subject] / [grade] / [semester] 用于「关联知识点场景」。
/// 课件孤儿（[knowledgePointId] 为 null）时该能力自动不可用。
Future<CoursewareSectionModel?> showCoursewareSectionEditDialog(
  BuildContext context,
  WidgetRef ref,
  CoursewareSectionModel section, {
  String? knowledgePointId,
  required String subject,
  required int grade,
  String semester = '',
}) =>
    showDialog<CoursewareSectionModel>(
      context: context,
      builder: (_) => _SectionEditDialog(
        section: section,
        knowledgePointId: knowledgePointId,
        subject: subject,
        grade: grade,
        semester: semester,
      ),
    );

class _SectionEditDialog extends ConsumerStatefulWidget {
  const _SectionEditDialog({
    required this.section,
    this.knowledgePointId,
    required this.subject,
    required this.grade,
    this.semester = '',
  });

  final CoursewareSectionModel section;

  /// 课件所属知识点 id（顶层关联）。null = 孤儿课件，无法关联场景。
  final String? knowledgePointId;
  final String subject;
  final int grade;
  final String semester;

  @override
  ConsumerState<_SectionEditDialog> createState() => _SectionEditDialogState();
}

class _SectionEditDialogState extends ConsumerState<_SectionEditDialog> {
  late final TextEditingController _titleCtl;
  late List<TextEditingController> _segCtls;
  late List<CoursewareScriptEmphasis> _segEmphasis;
  late CoursewareSectionModel _draft;

  /// `interactiveScene` 环节「关联知识点场景」：拉取的知识点模板与加载态。
  List<Map<String, dynamic>>? _kpScenes;
  bool _scenesLoading = false;

  @override
  void initState() {
    super.initState();
    _titleCtl = TextEditingController(text: widget.section.title);

    // 旧单串话术 → 包成一段；否则沿用既有段列表；两者皆空给一段空的便于直接输入。
    final seed = widget.section.scriptSegments.isNotEmpty
        ? widget.section.scriptSegments
        : (widget.section.script.isNotEmpty
            ? [CoursewareScriptSegment(text: widget.section.script)]
            : const [CoursewareScriptSegment()]);
    _segCtls = [for (final s in seed) TextEditingController(text: s.text)];
    _segEmphasis = [for (final s in seed) s.emphasis];

    _draft = widget.section;

    // 内容块统一化：旧 AI 起草数据（payload 内嵌 items / 整份 SceneSpec）打开即归一化
    // 到顶层 materials / scene，让统一表单只操作顶层字段、保存时不再写 legacy payload。
    _draft = _draft.copyWith(
      materials: _draft.resolvedMaterials,
      scene: _draft.resolvedScene,
    );

    // 关联知识点场景：进入即按知识点拉取其已配置的讲解模板（统一表单，任意 kind 都可用）。
    // 知识点没配 → 拉到空列表 → UI 提示去知识点页配置；孤儿课件则根本不拉。
    if (widget.knowledgePointId != null) {
      _loadKnowledgePointScenes();
    }
  }

  Future<void> _loadKnowledgePointScenes() async {
    if (widget.knowledgePointId == null) return;
    setState(() => _scenesLoading = true);
    try {
      final scenes = await ref.read(coursewareRepositoryProvider).getKnowledgePointScenes(
            kpId: widget.knowledgePointId!,
            subject: widget.subject,
            grade: widget.grade,
            semester: widget.semester,
          );
      if (!mounted) return;
      setState(() {
        _kpScenes = scenes;
        _scenesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _kpScenes = null;
        _scenesLoading = false;
      });
      AppToast.show(context, '读取知识点场景失败：$e');
    }
  }

  /// 选中一份知识点模板 → 快照式复制进本环节顶层 [CoursewareSectionModel.scene]
  /// （演示页直接渲染，见 [SectionInteractiveScene]）。这是「快照式」关联：复制进来，
  /// 不随知识点后续改动自动更新。
  void _associateScene(Map<String, dynamic> spec) => setState(
        () => _draft = _draft.copyWith(
          scene: Map<String, dynamic>.from(spec),
        ),
      );

  /// 清除关联：scene 置空，演示页回落到「只有话术」提示。
  void _clearAssociation() =>
      setState(() => _draft = _draft.copyWith(scene: null));

  @override
  void dispose() {
    _titleCtl.dispose();
    for (final c in _segCtls) {
      c.dispose();
    }
    super.dispose();
  }

  /// 把素材库 picker 回执的 `{items:[{asset_id,caption}]}` 解析成顶层素材列表。
  List<CoursewareMaterialItem> _materialsFromPicker(Map<String, dynamic> updated) {
    final raw = updated['items'];
    if (raw is! List) return const <CoursewareMaterialItem>[];
    return <CoursewareMaterialItem>[
      for (final e in raw)
        if (e is Map)
          CoursewareMaterialItem(
            assetId: (e['asset_id'] as String?) ?? '',
            caption: (e['caption'] as String?) ?? '',
          ),
    ];
  }

  /// 关联素材：复用素材库 picker；把它当前的顶层素材映射回 picker 用的 items 结构，
  /// 让 picker 能显示既有选择，回执再归一化回顶层 [CoursewareSectionModel.materials]。
  Future<void> _addAsset() async {
    final current = {
      'items': [
        for (final m in _draft.materials)
          {'asset_id': m.assetId, 'caption': m.caption},
      ],
    };
    final updated = await showCoursewareAssetPicker(
      context,
      ref,
      current: current,
    );
    if (updated == null) return;
    setState(
      () => _draft = _draft.copyWith(materials: _materialsFromPicker(updated)),
    );
  }

  void _removeMaterial(int index) {
    final mats = [..._draft.materials]..removeAt(index);
    setState(() => _draft = _draft.copyWith(materials: mats));
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
      // 内容块统一化：legacy payload 不再承担内容存储，统一落顶层 materials / scene。
      payload: const {},
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
                      const SizedBox(height: AppSpacing.lg),
                      // 关联素材（统一表单，任意 kind 都能挂）。
                      Text('关联素材', style: text.labelMedium),
                      const SizedBox(height: AppSpacing.sm),
                      ..._draft.materials.asMap().entries.map(
                            (e) => _materialRow(e.key, e.value, app, text),
                          ),
                      AppTextAction(label: '添加素材', onPressed: _addAsset),
                      const SizedBox(height: AppSpacing.lg),
                      // 关联知识点场景（统一表单，任意 kind 都能挂）。
                      SectionSceneAssociationBlock(
                        knowledgePointId: widget.knowledgePointId,
                        loading: _scenesLoading,
                        scenes: _kpScenes,
                        hasScene: _draft.scene != null,
                        onRetry: () {
                          _loadKnowledgePointScenes();
                        },
                        onAssociate: _associateScene,
                        onClear: _clearAssociation,
                      ),
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

  Widget _materialRow(
    int index,
    CoursewareMaterialItem item,
    AppColors app,
    AppText text,
  ) {
    final caption = item.caption;
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
            onPressed: () => _removeMaterial(index),
          ),
        ],
      ),
    );
  }
}
