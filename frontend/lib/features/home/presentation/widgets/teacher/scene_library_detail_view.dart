/// 场景详情（ADR-0073）：列出某个内置场景的**全部内置实例**。
///
/// 实例 = 引用了该 kind 的知识点。每个实例展示三件事：属于哪个知识点（含范围，
/// 因为知识点跨学期同名）、它实际配了什么（据此预览）、以及完整场景预览。
///
/// **预览复用 [SceneInterpreter]**，不另写一个查看器：观看 delegate 与课堂里学到的
/// 渲染路径是同一条，才不会出现「库里看着正常、题目里却不同」的漂移。这里喂的是
/// **知识点自己的 scenes**（含图形与顶点），而不是注册表的中性种子——中性种子没有
/// figure/points，渲染出来只是一个占位兜底图形，展示它等于误导。
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/domain/figures.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/widgets/scene_interpreter/reflection_figure_gallery.dart';
import '../../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';
import '../../../providers/home_provider.dart';
import '../../../domain/repositories/material_repository.dart';
import '../../../providers/knowledge_manage_provider.dart';
import 'scene_library_associate_dialog.dart';

class TeacherSceneLibraryDetailView extends ConsumerWidget {
  final String kind;
  final VoidCallback onBack;

  /// 点某个关联知识点时打开编辑器（走 sealed 导航，T02）：home_screen 在此把
  /// 该知识点翻成 `SceneLibraryEditorPage`，关闭统一回本详情页。
  final void Function(SceneLibraryKpRef kp) onOpenKp;

  const TeacherSceneLibraryDetailView({
    super.key,
    required this.kind,
    required this.onBack,
    required this.onOpenKp,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sceneLibraryProvider);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              AppIconAction(
                icon: Icons.arrow_back,
                semanticLabel: '返回场景库',
                onPressed: onBack,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text('场景实例', style: text.titleLarge)),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: Text('正在读取场景实例…')),
            error: (e, _) => _DetailEmpty(
              message: '场景实例读取失败',
              hint: '请检查服务是否可用后重试（$e）',
            ),
            data: (library) {
              final entry = library.scenes
                  .where((e) => e.kind == kind)
                  .firstOrNull;
              if (entry == null) {
                return const _DetailEmpty(
                  message: '场景不存在',
                  hint: '该内置场景可能已在版本更新后移除。',
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                children: [
                  // 库默认演示图形（ADR-0074 T03）：只 seed 新关联，不回写已关联。
                  _DefaultFigureSection(
                    kind: kind,
                    defaultFigureKey: entry.defaultFigureKey,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // 关联知识点区（ADR-0074 T04）：列已关联 KP，并提供关联入口。
                  Row(
                    children: [
                      Expanded(
                        child: Text('关联的知识点', style: text.titleSmall),
                      ),
                      AppTextAction(
                        label: '关联知识点',
                        onPressed: () => _showAssociate(ref, context, entry),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (entry.associatedKnowledgePoints.isEmpty)
                    _DetailEmpty(
                      message: '还没有知识点引用 ${entry.title}',
                      hint: '点上方「关联知识点」把它关联进来，它会出现在这里。',
                    )
                  else
                    for (final kp in entry.associatedKnowledgePoints)
                      _InstanceCard(
                        kp: kp,
                        fallbackKind: kind,
                        onOpen: () => onOpenKp(kp),
                        onUnlink: () => _unlink(ref, context, kp),
                      ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// 解除关联（ADR-0074 T04 §4）：从 KP 的 `scenes` 移除本 kind 条目，经现有
  /// `PATCH …/scenes` 保存；场景本身不被级联删除（ADR-0073 快照不变）。
  Future<void> _unlink(WidgetRef ref, BuildContext context, SceneLibraryKpRef kp) async {
    final kept = (kp.scenes ?? [])
        .where((s) => (s['kind'] as String? ?? '') != kind)
        .toList();
    try {
      await ref.read(materialRepositoryProvider).updateKnowledgePointScenes(
        kpId: kp.id,
        scenes: kept,
      );
      ref.invalidate(sceneLibraryProvider);
      if (!context.mounted) return;
      AppToast.show(context, '已解除关联');
    } catch (e) {
      if (!context.mounted) return;
      AppToast.show(context, '解除失败：$e');
    }
  }

  /// 打开「关联知识点」选择器（ADR-0074 T04 §3）：从教师已有、且未关联本 kind 的
  /// 知识点里挑一个，写一份 seed 场景进其 `scenes`。
  void _showAssociate(WidgetRef ref, BuildContext context, SceneLibraryEntry entry) {
    showAssociateKpDialog(
      context,
      entry: entry,
      associatedIds:
          entry.associatedKnowledgePoints.map((e) => e.id).toSet(),
      onAssociated: () {
        ref.invalidate(sceneLibraryProvider);
        AppToast.show(context, '已关联知识点');
      },
    );
  }
}

class _InstanceCard extends StatelessWidget {
  final SceneLibraryKpRef kp;
  final String fallbackKind;
  final VoidCallback onOpen;
  final VoidCallback? onUnlink;

  const _InstanceCard({
    required this.kp,
    required this.fallbackKind,
    required this.onOpen,
    this.onUnlink,
  });

  /// 该实例实际配的图形名；没配或识别不出返回 null（不臆造一个名字）。
  String? _figureLabel() {
    final scenes = kp.scenes;
    if (scenes == null || scenes.isEmpty) return null;
    final scene = scenes.first;
    final inputs = scene['inputs'];
    if (inputs is! List) return null;
    for (final e in inputs) {
      if (e is Map && e['key'] == 'figure') {
        final key = e['value']?.toString() ?? '';
        if (key.isEmpty) return null;
        return figureByKey(key).label;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    final label = _figureLabel();
    final scene = kp.scenes?.firstOrNull;
    final card = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: app.surface,
        border: Border.all(
          color: app.outline,
          width: AppElevation.borderWidthSm,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kp.name, style: text.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${kp.grade}年级${kp.subject} · ${kp.semester}',
                        style: text.bodySmall
                            ?.copyWith(color: app.onSurfaceVariant),
                      ),
                      if (kp.kpMissing)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            '关联的知识点已不存在',
                            style: text.bodySmall
                                ?.copyWith(color: app.error),
                          ),
                        ),
                      if (label != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text('图形：$label', style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
                // 解除关联（ADR-0074 T04）：从 KP 的 scenes 移除该 kind 条目；
                // prune 悬空项也保留此入口以便清理聚余。
                if (onUnlink != null)
                  AppTextAction(
                    label: '解除关联',
                    color: app.error,
                    semanticLabel: '解除关联',
                    onPressed: onUnlink,
                  ),
              ],
            ),
            if (scene != null) ...[
              const SizedBox(height: AppSpacing.sm),
              // 预览缩略图：只画画布本身，摘掉交互外壳（播放条/编辑滑块/讲解词）。
              // ReflectionSceneWidget 以约束 maxWidth 作正方形边长（画布 140×140），
              // 但其下方还有状态条 + 播放条 + 3 个轴滑块 + 讲解词，整块约需 437px；
              // 若把预览钉死 140 高，会触发 RenderFlex 溢出约 297px（ADR-0074 T04
              // 渲染修复）。这里只限宽（140），让预览按自然高度（画布 + 状态条）
              // 排布——既不溢出，也保留「该知识点配了什么图形」的预览。
              SizedBox(
                width: 140,
                child: SceneInterpreter(
                  kind: (scene['kind'] as String?) ?? fallbackKind,
                  // 保留 figure/points/axis（学生真实配置），只摘掉交互外壳。
                  spec: <String, dynamic>{
                    ...scene,
                    'editable': false,
                    'controls': const <String, dynamic>{},
                    'narrative': null,
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
    // 整卡可点：打开该知识点的讲解编辑器（走 sealed 导航）。内层「解除关联」
    // 自身也是可聚焦动作，点击它只会触发自身、不会冒泡到整卡（ADR-0046）。
    return AppFocusableAction(
      onTap: onOpen,
      semanticLabel: '编辑 ${kp.name} 的讲解',
      child: card,
    );
  }
}

class _DetailEmpty extends StatelessWidget {
  final String message;
  final String hint;

  const _DetailEmpty({required this.message, required this.hint});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: text.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              hint,
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 场景库「默认演示图形」配置区（ADR-0074 T03）。
///
/// 教师在这里挑一个图形设为该 kind 的默认：新关联的知识点按它初始化讲解图形，
/// **已关联的知识点不受影响**（绝不回写 `kp.scenes`，ADR-0073 快照不可变）。
/// 画廊复用 [ReflectionFigureGallery]，选中的那张卡标「默认讲解」徽标。
class _DefaultFigureSection extends ConsumerStatefulWidget {
  final String kind;
  final String? defaultFigureKey;

  const _DefaultFigureSection({
    required this.kind,
    this.defaultFigureKey,
  });

  @override
  ConsumerState<_DefaultFigureSection> createState() =>
      _DefaultFigureSectionState();
}

class _DefaultFigureSectionState extends ConsumerState<_DefaultFigureSection> {
  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('默认演示图形', style: text.titleSmall)),
            if (widget.defaultFigureKey != null)
              AppTextAction(
                label: '清除默认',
                onPressed: () => _set(null),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '新关联的知识点按此默认图形初始化讲解；已关联的知识点不受影响。',
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        ReflectionFigureGallery(
          figures: kFigureShapes,
          selectedKey: widget.defaultFigureKey,
          hint: '点一个图形设为该场景的默认演示图形',
          onOpen: (figure) => _set(figure.key),
        ),
      ],
    );
  }

  Future<void> _set(String? figureKey) async {
    try {
      await ref
          .read(materialRepositoryProvider)
          .saveSceneDefaultFigure(kind: widget.kind, figureKey: figureKey);
      // 刷新场景库清单，让画廊选中态与「清除默认」入口跟随新值。
      ref.invalidate(sceneLibraryProvider);
      if (!mounted) return;
      if (figureKey == null) {
        AppToast.show(context, '已清除默认图形');
      } else {
        AppToast.show(context, '已设为默认图形：${figureByKey(figureKey).label}');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '设置失败：$e');
    }
  }
}
