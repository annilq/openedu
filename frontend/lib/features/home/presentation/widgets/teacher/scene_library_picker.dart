/// 内置交互讲解场景选择（ADR-0073）：把后端**登记**的 kind 摆出来，选中后由调用方
/// 拿它的 `defaults` 预填模板。
///
/// 为什么清单要由后端下发：kind 是「前端有渲染器 + 后端有词汇表」的**双登记产物**
/// （ADR-0061 §O），教师在前端不可能凭空知道后端这版实现了哪些场景。硬编码一份
/// 下拉在前端，等于承诺「这两个列表永远同步」——而它们恰恰最容易漂移。
///
/// 刻意做得很克制：**不渲染任何参数表单**。参数表单是给「调默认值」用的，而默认值
/// 属于开发者维护的内置定义（这就是「未配置时弹开发者指引」那条纪律的来由）。这里
/// 只回答一个问题——「用哪个 kind 作为模板起点」。
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../domain/repositories/material_repository.dart';
import '../../../providers/knowledge_manage_provider.dart';

class SceneLibraryPicker extends ConsumerWidget {
  final ValueChanged<SceneLibraryEntry> onPick;

  const SceneLibraryPicker({super.key, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sceneLibraryProvider);
    final app = AppTheme.colorsOf(context);
    // 拉不到清单时**静默隐身**而不是报错：这只是「选 kind 的快捷入口」，知识点的
    // 讲解照旧可用（已有 scenes 的会直接渲染表单），不该因为清单拉取失败就挡住
    // 编辑，更不该让教师去理解一个跟自己无关的后端错误。
    return async.maybeWhen(
      data: (library) => library.scenes.isEmpty
          ? const SizedBox.shrink()
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in library.scenes)
                  _EntryTile(
                    entry: entry,
                    accent: app.primary,
                    onTap: () => onPick(entry),
                  ),
              ],
            ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final SceneLibraryEntry entry;
  final Color accent;
  final VoidCallback onTap;

  const _EntryTile({
    required this.entry,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        border: Border.all(
          color: accent,
          width: AppElevation.borderWidthSm,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: AppFocusableAction(
        onTap: onTap,
        semanticLabel: '选择内置场景 ${entry.title}',
        hoverHighlight: true,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, style: text.labelMedium),
                    const SizedBox(height: 2),
                    Text(
                      'kind：${entry.kind}'
                      '${entry.instanceCount > 0 ? ' · 已用于 ${entry.instanceCount} 个知识点' : ''}',
                      style: text.bodySmall
                          ?.copyWith(color: app.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right, size: 18, color: app.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
