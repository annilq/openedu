/// 场景详情（ADR-0073）：列出某个内置场景的**全部内置实例**。
///
/// 实例 = 引用了该 kind 的知识点。每个实例展示两件事：属于哪个知识点（含范围，
/// 因为知识点跨学期同名），以及它实际配的场景预览——预览画布就是「配了什么」的
/// 唯一答案（新形 SceneSpec 是纯几何、不带图形名，故不再单列一个名字标签）。
///
/// **预览复用 [SceneInterpreter]**，不另写一个查看器：观看 delegate 与课堂里学到的
/// 渲染路径是同一条，才不会出现「库里看着正常、题目里却不同」的漂移。这里喂的是
/// **知识点自己的 scenes**（内联顶点），而不是注册表的中性种子——中性种子没有
/// `points`，渲染出来只是一个占位兜底图形，展示它等于误导。
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/widgets/scene_interpreter/figure_library_gallery.dart';
import '../../../../../shared/widgets/scene_interpreter/reflection_figure_gallery.dart';
import '../../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';
import '../../../providers/home_provider.dart';
import '../../../domain/repositories/material_repository.dart';
import '../../../providers/knowledge_manage_provider.dart';
import 'scene_library_associate_dialog.dart';
part 'scene_library_default_figure_section.dart';

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
        // 关联 / 解绑写回后刷新库清单（对话框自身按动作给出 toast 提示）。
        ref.invalidate(sceneLibraryProvider);
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

  /// 优先取「kind == 本页 kind」的场景——即把该 KP 关联到本页的那条。
  /// 找不到（理论上不该发生，关联就是靠这条 kind 把 KP 拉进列表）才退回首个，
  /// 避免同一 KP 配了多种场景时，卡片预览显示成别的 kind，造成
  /// 「场景页里看到另一个场景」的错觉（ADR-0074 关联列表）。
  Map<String, dynamic>? _sceneForKind() {
    final scenes = kp.scenes;
    if (scenes == null || scenes.isEmpty) return null;
    return scenes.firstWhere(
      (s) => (s['kind'] as String? ?? '') == fallbackKind,
      orElse: () => scenes.first,
    );
  }

  // 这里**不**再显示「图形：<名字>」：新形 SceneSpec 是纯几何、不带图形名
  // （ADR-0083 决策 6 删 `figure` 引用键），要拿名字就得回查图库——而展示层
  // 不该为了一个标签欠一次取数。想知道配了什么，看下面的预览画布即可。

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    final scene = _sceneForKind();
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
              // 预览缩略图：只画画布本身，不挂轴滑块。
              // ReflectionSceneWidget 以约束 maxWidth 作正方形边长（画布 140×140），
              // 但其下方还有 3 个轴滑块（每个 84 + 44 固定宽 + 滑轨，140 宽下挤成
              // 几像素、放不下）——缩略图里一律摘掉（ADR-0074 T04 渲染修复）。
              // 「摘掉」是**展示开关**（[SceneInterpreter.showAxisControls]），不再往
              // spec 里塞已废的 `editable`/`controls`/`narrative`（ADR-0083 决策 5：
              // 交互与文案归 kind 外壳，spec 只留几何）。
              SizedBox(
                width: 140,
                child: SceneInterpreter(
                  kind: (scene['kind'] as String?) ?? fallbackKind,
                  // 直接把知识点自己的场景喂进去（几何是唯一权威），不再改写 spec。
                  spec: scene,
                  showAxisControls: false,
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
