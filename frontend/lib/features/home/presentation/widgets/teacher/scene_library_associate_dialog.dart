/// 场景库「关联知识点」选择器（ADR-0074 T04 §3）。
///
/// 从教师**已有且未关联本 kind** 的知识点里挑一个，写一份 seed 场景经现有
/// `PATCH …/scenes` 进该 KP。seed 图形取自库默认（`default_figure_key`，空则
/// 回落空占位），轴参数取注册表中性种子——与知识点编辑器保存走同一份结构
/// （[buildReflectionSceneSpec]），不在此另造一份。
///
/// 前端按范围过滤未关联项（零后端改动）：先选 (学科, 年级, 学期) 范围，再列出该
/// 范围内未被本 kind 关联的知识点。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/figures.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/widgets/scene_interpreter/reflection_scene_data.dart';
import '../../../domain/repositories/material_repository.dart';
import '../../../providers/home_provider.dart';

/// 打开关联选择器。
///
/// [associatedIds] 是当前已关联本 kind 的知识点 id 集合，用于过滤掉不可再选的项。
/// [onAssociated] 在 seed 写入成功后回调（调用方负责刷新场景库清单 + 提示）。
void showAssociateKpDialog(
  BuildContext context, {
  required SceneLibraryEntry entry,
  required Set<String> associatedIds,
  required VoidCallback onAssociated,
}) {
  showShadDialog(
    context: context,
    barrierColor: AppTheme.colorsOf(context).scrim,
    builder: (ctx) => _AssociateKpDialog(
      entry: entry,
      associatedIds: associatedIds,
      onAssociated: onAssociated,
    ),
  );
}

class _AssociateKpDialog extends ConsumerStatefulWidget {
  final SceneLibraryEntry entry;
  final Set<String> associatedIds;
  final VoidCallback onAssociated;

  const _AssociateKpDialog({
    required this.entry,
    required this.associatedIds,
    required this.onAssociated,
  });

  @override
  ConsumerState<_AssociateKpDialog> createState() => _AssociateKpDialogState();
}

class _AssociateKpDialogState extends ConsumerState<_AssociateKpDialog> {
  List<KnowledgePointScope> _scopes = const [];
  KnowledgePointScope? _scope;
  List<KnowledgePointOption> _items = const [];
  bool _loading = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadScopes();
  }

  Future<void> _loadScopes() async {
    setState(() => _loading = true);
    try {
      final res = await ref
          .read(materialRepositoryProvider)
          .getKnowledgePointScopes();
      if (!mounted) return;
      final scopes = [...res.scopes]
        ..sort((a, b) {
          final c = a.subject.compareTo(b.subject);
          if (c != 0) return c;
          final g = a.grade.compareTo(b.grade);
          if (g != 0) return g;
          return a.semester.compareTo(b.semester);
        });
      setState(() {
        _scopes = scopes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载范围失败：$e';
      });
    }
  }

  Future<void> _selectScope(KnowledgePointScope scope) async {
    setState(() {
      _scope = scope;
      _loading = true;
      _error = null;
    });
    try {
      final dir = await ref.read(materialRepositoryProvider).getKnowledgePointDirectory(
        subject: scope.subject,
        grade: scope.grade,
        semester: scope.semester,
      );
      if (!mounted) return;
      // 过滤掉已关联本 kind 的知识点：不能重复关联。
      final items = dir.items
          .where((e) => e.id != null && !widget.associatedIds.contains(e.id))
          .toList();
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载知识点失败：$e';
      });
    }
  }

  Future<void> _associate(KnowledgePointOption kp) async {
    if (_busy || kp.id == null) return;
    setState(() => _busy = true);
    try {
      // seed 场景：图形取库默认（空则回落空占位），轴参数取注册表中性种子。
      final data = ReflectionSceneData.fromSpec(widget.entry.defaults);
      final figureKey = widget.entry.defaultFigureKey;
      final shape = figureKey != null ? figureByKey(figureKey) : null;
      final points = (shape?.vertices ?? [])
          .map((v) => <double>[v.x, v.y])
          .toList(growable: false);
      final seed = buildReflectionSceneSpec(
        kind: widget.entry.kind,
        title: widget.entry.title,
        axisAngle: data.axisAngle,
        axisX: data.axisX,
        axisY: data.axisY,
        figureKey: figureKey ?? '',
        points: points,
      );
      // 保留该 KP 既有其它 kind 的场景，仅追加本 kind 的 seed（ADR-0073 快照不变）。
      final newScenes = <Map<String, dynamic>>[...(kp.scenes ?? []), seed];
      await ref.read(materialRepositoryProvider).updateKnowledgePointScenes(
        kpId: kp.id!,
        scenes: newScenes,
      );
      if (!mounted) return;
      widget.onAssociated();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '关联失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    String scopeLabel(KnowledgePointScope s) =>
        '${s.subject} ${s.grade}年级${s.semester.isEmpty ? '' : ' · ${s.semester}'}';
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('先选范围，再挑一个知识点关联进来。', style: text.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        if (_scopes.isEmpty && !_loading)
          Text('还没有可关联的知识点（先去资料库上传教材并提取知识点）。',
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant))
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final s in _scopes)
                AppFocusableAction(
                  onTap: () => _selectScope(s),
                  semanticLabel: '选择范围 ${scopeLabel(s)}',
                  hoverHighlight: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _scope == s ? app.accent : app.outline,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(scopeLabel(s), style: text.labelMedium),
                  ),
                ),
            ],
          ),
        if (_scope != null) ...[
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text('加载中…'),
              ),
            )
          else if (_items.isEmpty)
            Text('该范围下已无可关联的知识点。',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final kp in _items)
                  AppFocusableAction(
                    onTap: () => _associate(kp),
                    semanticLabel: '关联 ${kp.name}',
                    hoverHighlight: true,
                    child: Container(
                      margin:
                          const EdgeInsets.only(bottom: AppSpacing.xs),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: app.outline,
                          width: AppElevation.borderWidthSm,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(kp.name, style: text.bodyMedium),
                    ),
                  ),
              ],
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: text.bodySmall?.copyWith(color: app.error)),
        ],
      ],
    );
    return ShadDialog(
      closeIcon: const SizedBox.shrink(),
      title: const Text('关联知识点'),
      actions: [
        ShadButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: text.labelMedium?.copyWith(color: app.onPrimary),
          ),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: SingleChildScrollView(child: body),
      ),
    );
  }
}
