import 'dart:convert';

import 'package:flutter/material.dart' show Dialog, showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_image_viewer.dart';
import '../../../../shared/widgets/auth_image.dart';
import '../../domain/models/courseware_asset.dart';
import '../../domain/models/courseware_section.dart';
import '../../providers/courseware_provider.dart';
import 'asset_library_picker.dart';
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

  /// 当前选中的模板在 [_kpScenes] 中的下标；null = 未关联 / 已清除 / 源模板已失效。
  /// 场景模板是裸 dict、无稳定 id，下标是单次弹窗内唯一可靠标识。
  int? _selectedSceneIndex;

  @override
  void initState() {
    super.initState();
    _titleCtl = TextEditingController(text: widget.section.title);

    // 旧单串话术 → 包成一段；否则沿用既有段列表；两者皆空给一段空的便于直接输入。
    final seed = widget.section.scriptSegments.isNotEmpty
        ? widget.section.scriptSegments
        : (widget.section.script.isNotEmpty
            ? [CoursewareScriptSegment(text: widget.section.script)]
            : const <CoursewareScriptSegment>[]);
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
        // 重开已有课件：把顶层已关联的 scene 与拉到的模板做内容深比较，回填下标；
        // 找不到（知识点模板已改）则下标置 null，由 block 的 hasScene 提示源已失效。
        if (_draft.scene != null && scenes != null) {
          final idx = scenes.indexWhere((s) => _sceneEquals(s, _draft.scene!));
          _selectedSceneIndex = idx >= 0 ? idx : null;
        }
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

  /// 模板 dict 是裸 dict、无 id，用 JSON 字符串做内容深比较（dict 来自 JSON 解码，
  /// 键顺序稳定）。
  static bool _sceneEquals(Map<String, dynamic> a, Map<String, dynamic> b) =>
      jsonEncode(a) == jsonEncode(b);

  /// 在下拉里选中一份知识点模板 → 快照式复制进本环节顶层 [CoursewareSectionModel.scene]
  /// （演示页直接渲染，见 [SectionInteractiveScene]）。这是「快照式」关联：复制进来，
  /// 不随知识点后续改动自动更新。
  void _onSceneSelected(int index) => setState(() {
        _selectedSceneIndex = index;
        _draft = _draft.copyWith(
          scene: _kpScenes == null
              ? null
              : Map<String, dynamic>.from(_kpScenes![index]),
        );
      });

  /// 清除关联：scene 置空，演示页回落到「只有话术」提示。
  void _clearAssociation() => setState(() {
        _selectedSceneIndex = null;
        _draft = _draft.copyWith(scene: null);
      });

  @override
  void dispose() {
    _titleCtl.dispose();
    for (final c in _segCtls) {
      c.dispose();
    }
    super.dispose();
  }

  /// 关联素材：复用多选素材库 picker（ADR-0076）。当前已挂在环节里的素材 id 作为
  /// 「已选」传给 picker；回执是选中的 asset id 列表。落库时：保留既有素材的 caption、
  /// 按 picker 顺序重排、剔除未选中的、新选中的给空 caption。
  Future<void> _addAsset() async {
    final selectedIds = await showAssetLibraryPicker(
      context,
      ref,
      initialSelected: _draft.materials.map((m) => m.assetId).toList(),
    );
    if (selectedIds == null) return;
    final captionById = {
      for (final m in _draft.materials) m.assetId: m.caption,
    };
    final mats = <CoursewareMaterialItem>[
      for (final id in selectedIds)
        CoursewareMaterialItem(
          assetId: id,
          caption: captionById[id] ?? '',
        ),
    ];
    setState(() => _draft = _draft.copyWith(materials: mats));
  }

  void _removeMaterial(String assetId) {
    final mats =
        _draft.materials.where((m) => m.assetId != assetId).toList();
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
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: (MediaQuery.of(context).size.height - 96).clamp(560, 820),
        ),
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
                      _materialGrid(app, text),
                      const SizedBox(height: AppSpacing.lg),
                      // 关联知识点场景（统一表单，任意 kind 都能挂）。
                      SectionSceneAssociationBlock(
                        knowledgePointId: widget.knowledgePointId,
                        loading: _scenesLoading,
                        scenes: _kpScenes,
                        selectedIndex: _selectedSceneIndex,
                        hasScene: _draft.scene != null,
                        onRetry: () {
                          _loadKnowledgePointScenes();
                        },
                        onSelectedIndex: _onSceneSelected,
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
            onPressed: () => _removeSegment(index),
          ),
        ],
      ),
    );
  }

  /// 关联素材网格（ADR-0076）：每张素材一个缩略图，点缩略图放大看原图，右上角删除。
  /// 与 [SectionMediaGallery] 共用 `coursewareAssetsProvider` 解析 id→图；素材被删
  /// 后引用仍在的显示「素材已移除」占位。
  Widget _materialGrid(AppColors app, AppText text) {
    if (_draft.materials.isEmpty) {
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
          for (final m in _draft.materials)
            _MaterialTile(
              item: m,
              asset: list.where((a) => a.id == m.assetId).firstOrNull,
              onOpen: () {
                final a = list.where((x) => x.id == m.assetId).firstOrNull;
                if (a != null) showImageViewer(context, url: a.url, name: a.name);
              },
              onRemove: () => _removeMaterial(m.assetId),
            ),
        ],
      ),
    );
  }
}

/// 环节素材缩略图（ADR-0076）：点图放大看原图，右上角删除；找不到对应素材时显示
/// 「素材已移除」占位（不级联删除，引用保留）。
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
