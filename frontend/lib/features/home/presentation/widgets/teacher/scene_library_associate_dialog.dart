/// 场景库「关联知识点」选择器（ADR-0074 T04 §3）。
///
/// 弹出后**展示该范围内的全部知识点**，已关联本 kind 的项以「已关联」勾选态标出，
/// 用户点按即可切换：未关联的 → 写一份 seed 场景经 `PATCH …/scenes` 关联进来；
/// 已关联的 → 从 `kp.scenes` 移除本 kind 条目解除绑定。一处完成关联 / 解绑，
/// 不必退回列表再走另一条路径。
///
/// seed 图形取自库默认（`default_figure_key`，空则回落空占位），轴参数取注册表
/// 中性种子——与知识点编辑器保存走同一份结构（[buildReflectionSceneSpec]），不在此
/// 另造一份。切换为即时写回 + 本地勾选态翻转，对话框保持打开以支持连续多选。
/// 前端按范围列全部项（零后端改动）：默认选中第一个 (学科, 年级, 学期) 范围并立即
/// 列出该范围下所有知识点（避免弹窗空态），用户也可点选其它范围切换。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/figures.dart';
import '../../../../../shared/domain/providers/figure_library_provider.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../../shared/widgets/scene_interpreter/reflection_scene_data.dart';
import '../../../domain/repositories/material_repository.dart';
import '../../../providers/home_provider.dart';

/// 打开关联选择器。
///
/// [associatedIds] 是当前已关联本 kind 的知识点 id 集合，用于初始化勾选态
/// （已关联的项在列表里标「已关联」、可直接点按解除）。所有项都会展示，不再过滤。
/// [onAssociated] 在每次关联 / 解绑写回成功后回调（调用方负责刷新场景库清单）。
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

  /// 本地勾选态：已关联本 kind 的知识点 id 集合。初始化自 [widget.associatedIds]，
  /// 每次切换（关联 / 解绑）即时翻转，保证对话框内勾选与后端写回一致。
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.associatedIds.where((e) => e.isNotEmpty));
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
      // 默认选中第一个范围：进弹窗即展示知识点，免去「先点范围」才出数据的空态
      // （用户反馈：默认进去没数据、看不出可点）。
      if (scopes.isNotEmpty) {
        _selectScope(scopes.first);
      }
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
      // 展示该范围下全部知识点：已关联的靠 _selected 标「已关联」勾选态，
      // 不在此过滤（用户点按即可切换解绑，见 _toggle）。
      setState(() {
        _items = dir.items;
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

  /// 点按某项：已勾选 → 解绑；未勾选 → 关联。对话框保持打开以连续多选。
  Future<void> _toggle(KnowledgePointOption kp) async {
    if (_busy || kp.id == null) return;
    if (_selected.contains(kp.id)) {
      await _unlink(kp);
    } else {
      await _associate(kp);
    }
  }

  /// 关联：写一份本 kind 的 seed 进 `kp.scenes`（保留其它 kind 的场景，ADR-0073 快照不变）。
  Future<void> _associate(KnowledgePointOption kp) async {
    if (_busy || kp.id == null) return;
    setState(() => _busy = true);
    try {
      // seed 场景：图形取库默认（空则回落空占位）。ADR-0083：spec 是纯几何
      // `{kind, points, edges}`——轴初值/控件/文案由 kind 外壳提供，不进 spec。
      //
      // 几何只能来自图库（ADR-0083 决策 1/6：「默认图形」存的是 key，几何在表里）。
      // 这里按需把图库拉一次；拉不到就退回空顶点（渲染端会兜到中性图形），**不**因此
      // 让整次关联失败——关联本身与图库可用性是两件事。
      final figureKey = widget.entry.defaultFigureKey;
      var points = const <List<double>>[];
      if (figureKey != null && figureKey.isNotEmpty) {
        final shape = await _defaultFigure(figureKey);
        points = <List<double>>[
          for (final v in shape?.vertices ?? const <({double x, double y})>[])
            <double>[v.x, v.y],
        ];
      }
      final seed = buildReflectionSceneSpec(
        kind: widget.entry.kind,
        points: points,
        edges: closedEdges(points.length),
      );
      // 保留该 KP 既有其它 kind 的场景，仅追加本 kind 的 seed（ADR-0073 快照不变）。
      final newScenes = <Map<String, dynamic>>[...(kp.scenes ?? []), seed];
      await ref.read(materialRepositoryProvider).updateKnowledgePointScenes(
        kpId: kp.id!,
        scenes: newScenes,
      );
      if (!mounted) return;
      setState(() {
        _selected.add(kp.id!);
        _busy = false;
      });
      widget.onAssociated();
      AppToast.show(context, '已关联 ${kp.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '关联失败：$e';
      });
    }
  }

  /// 按 key 取库默认图形的几何（图库按需拉取，ADR-0083 决策 7）。
  ///
  /// 图库读不出来 → 返回 null（调用方退回空顶点），绝不兜到某个内置图形上：
  /// 给一个与教师所选无关的图形，比给一个中性占位更糟（会教错）。
  Future<FigureShape?> _defaultFigure(String key) async {
    try {
      final library = await ref.read(figureLibraryProvider.future);
      for (final f in library) {
        if (f.key == key) return f;
      }
    } catch (_) {
      // 网络/解析失败与「关联」无关，交给上面的空顶点分支。
    }
    return null;
  }

  /// 解绑：从 `kp.scenes` 移除本 kind 的条目（保留其它 kind），经 `PATCH …/scenes` 写回。
  Future<void> _unlink(KnowledgePointOption kp) async {
    if (_busy || kp.id == null) return;
    setState(() => _busy = true);
    try {
      final kept = (kp.scenes ?? [])
          .where((s) => (s['kind'] as String? ?? '') != widget.entry.kind)
          .toList();
      await ref.read(materialRepositoryProvider).updateKnowledgePointScenes(
        kpId: kp.id!,
        scenes: kept,
      );
      if (!mounted) return;
      setState(() {
        _selected.remove(kp.id);
        _busy = false;
      });
      widget.onAssociated();
      AppToast.show(context, '已解除 ${kp.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '解除失败：$e';
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
        Text('已默认展示第一个范围的知识点；点按任一项即可关联或解除。',
            style: text.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        Text('选择范围',
            style: text.labelMedium?.copyWith(color: app.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.xs),
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
                      color: _scope == s ? app.accent : app.surfaceRaised,
                      border: Border.all(
                        color: _scope == s ? app.accent : app.outline,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      scopeLabel(s),
                      style: text.labelMedium?.copyWith(
                        color: _scope == s ? app.onPrimary : app.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (_scope != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text('知识点（点按切换关联）',
              style: text.labelMedium?.copyWith(color: app.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.xs),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text('加载中…'),
              ),
            )
          else if (_items.isEmpty)
            Text('该范围下没有知识点。',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final kp in _items)
                  _kpTile(kp, text, app),
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

  /// 单条知识点：整行可点按切换关联。已关联 → 方块内 ✓ 填色 + 「已关联」标签；
  /// 未关联 → 方块内 + 图标 + 「关联」标签，明确提示「点我即可关联」，消除
  /// 「看不出能点」的歧义（用户反馈）。整行 hover 高亮进一步显出可交互。
  Widget _kpTile(KnowledgePointOption kp, AppText text, AppColors app) {
    final selected = kp.id != null && _selected.contains(kp.id);
    return AppFocusableAction(
      onTap: () => _toggle(kp),
      semanticLabel: selected ? '解除关联 ${kp.name}' : '关联 ${kp.name}',
      hoverHighlight: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? app.accent : app.outline,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: selected ? app.accent : app.surfaceRaised,
                border: Border.all(
                  color: selected ? app.accent : app.outline,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                selected ? LucideIcons.check : LucideIcons.plus,
                size: 14,
                color: selected ? app.onPrimary : app.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(kp.name, style: text.bodyMedium)),
            Text(
              selected ? '已关联' : '关联',
              style: text.labelSmall?.copyWith(
                color: selected ? app.accent : app.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
