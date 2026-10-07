/// 场景库列表页（ADR-0073）：教师查看「后端登记了哪些内置交互讲解场景」。
///
/// 每项回答三件事：场景名、它被哪些知识点引用、以及内置实例数量。
///
/// **实例口径只有内置参考**——已生成的题目 / 课件快照不在这里出现。那些是
/// 「生成时刻的拷贝」，归它们自己的页面渲染；塞进这张清单的话，计数会随每次出题
/// 一直涨，教师再也对不上「为什么昨天 3 个、今天 17 个」。
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../domain/repositories/material_repository.dart';
import '../../../providers/knowledge_manage_provider.dart';

class TeacherSceneLibraryView extends ConsumerWidget {
  final void Function(String kind) onOpenScene;

  const TeacherSceneLibraryView({super.key, required this.onOpenScene});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sceneLibraryProvider);
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('场景库', style: text.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '内置交互讲解场景由开发者随发版登记，这里列出每个场景被哪些知识点'
                '引用。已生成的题目与课件不在此列——它们的场景在自己的页面里显示。',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: Text('正在读取场景库…')),
            error: (e, _) => _EmptyNotice(
              message: '场景库读取失败',
              hint: '请检查服务是否可用后重试（$e）',
            ),
            data: (library) {
              if (library.scenes.isEmpty) {
                return const _EmptyNotice(
                  message: '后端尚未登记任何内置场景',
                  hint: '内置场景随版本发布；升级后这里会自动出现。',
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
                  for (final entry in library.scenes)
                    _SceneCard(
                      entry: entry,
                      onTap: () => onOpenScene(entry.kind),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SceneCard extends StatelessWidget {
  final SceneLibraryEntry entry;
  final VoidCallback onTap;

  const _SceneCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    final refs = entry.associatedKnowledgePoints;
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
      child: AppFocusableAction(
        onTap: onTap,
        semanticLabel: '查看场景 ${entry.title} 的全部实例',
        hoverHighlight: true,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(entry.title, style: text.titleMedium),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.chevron_right, size: 18, color: app.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('kind：${entry.kind}', style: text.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '内置实例 ${entry.instanceCount} 个',
                style: text.labelMedium?.copyWith(color: app.primary),
              ),
              if (refs.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final ref in refs.take(6))
                      Text(
                        '${ref.grade}年级${ref.subject}·${ref.name}',
                        style: text.bodySmall
                            ?.copyWith(color: app.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 空态（ADR-0051）：必须同时回答「为什么空」与「下一步做什么」。
class _EmptyNotice extends StatelessWidget {
  final String message;
  final String hint;

  const _EmptyNotice({required this.message, required this.hint});

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
