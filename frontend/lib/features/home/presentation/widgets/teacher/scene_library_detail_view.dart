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
import '../../../../../shared/widgets/scene_interpreter/reflection_figure_gallery.dart';
import '../../../../../shared/widgets/scene_interpreter/scene_interpreter.dart';
import '../../../providers/home_provider.dart';
import '../../../domain/repositories/material_repository.dart';
import '../../../providers/knowledge_manage_provider.dart';

class TeacherSceneLibraryDetailView extends ConsumerWidget {
  final String kind;
  final VoidCallback onBack;

  const TeacherSceneLibraryDetailView({
    super.key,
    required this.kind,
    required this.onBack,
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
                  if (entry.associatedKnowledgePoints.isEmpty)
                    _DetailEmpty(
                      message: '还没有知识点引用 ${entry.title}',
                      hint: '在下方「关联知识点」里把某个知识点关联进来，它会出现在这里。',
                    )
                  else
                    for (final kp in entry.associatedKnowledgePoints)
                      _InstanceCard(kp: kp, fallbackKind: kind),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InstanceCard extends StatelessWidget {
  final SceneLibraryKpRef kp;
  final String fallbackKind;

  const _InstanceCard({required this.kp, required this.fallbackKind});

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
    return Container(
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
            Text(kp.name, style: text.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${kp.grade}年级${kp.subject} · ${kp.semester}',
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
            ),
            if (label != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('图形：$label', style: text.bodySmall),
            ],
            if (scene != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 140,
                child: SceneInterpreter(
                  kind: (scene['kind'] as String?) ?? fallbackKind,
                  spec: scene,
                ),
              ),
            ],
          ],
        ),
      ),
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
