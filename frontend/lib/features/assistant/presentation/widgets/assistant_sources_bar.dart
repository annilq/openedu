import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../domain/assistant_source.dart';

/// 答疑答案下方的「参考来源」条：把本次命中并注入 prompt 的资料片段溯源列出来，
/// 直接回答「这条回答引用了资料库里的哪些内容」（ADR-0055 §13 引用透明）。
///
/// 单份资料可能命中多个片段：按 `materialId` 去重，片段拼接展示。点击资料名可展开
/// 看实际注入的片段摘要（清洗后的 snippet），让教师 / 学生核对出处。
class AssistantSourcesBar extends StatefulWidget {
  final List<RagSource> sources;

  const AssistantSourcesBar({super.key, required this.sources});

  @override
  State<AssistantSourcesBar> createState() => _AssistantSourcesBarState();
}

class _AssistantSourcesBarState extends State<AssistantSourcesBar> {
  final Set<String> _expanded = {};

  /// 按资料去重：同资料多片段拼成一条。
  List<RagSource> get _deduped {
    final byMaterial = <String, RagSource>{};
    for (final s in widget.sources) {
      if (s.materialId.isEmpty) continue;
      final existing = byMaterial[s.materialId];
      if (existing == null) {
        byMaterial[s.materialId] = s;
      } else {
        byMaterial[s.materialId] = RagSource(
          materialId: s.materialId,
          materialName: s.materialName,
          chunkId: s.chunkId,
          snippet: '${existing.snippet}\n${s.snippet}'.trim(),
        );
      }
    }
    return byMaterial.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final items = _deduped;
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(
        top: 2,
        left: 4,
        bottom: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '参考来源',
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final s in items)
                _SourceChip(
                  source: s,
                  expanded: _expanded.contains(s.materialId),
                  onTap: () => setState(() {
                    if (_expanded.contains(s.materialId)) {
                      _expanded.remove(s.materialId);
                    } else {
                      _expanded.add(s.materialId);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final RagSource source;
  final bool expanded;
  final VoidCallback onTap;

  const _SourceChip({
    required this.source,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 不用 InkWell：App 根是 CupertinoApp/ShadApp，子树**没有 Material 祖先**，
        // InkWell 会在构建期直接抛「No Material widget found」（整棵消息流崩掉，
        // 不是某个按钮失灵）。也不留裸 GestureDetector——它不进焦点树，桌面端 Tab
        // 跳不过来、Enter 点不动，而 `flutter analyze` 照不出来（ADR-0046）。
        AppFocusableAction(
          onTap: onTap,
          hoverHighlight: true,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          semanticLabel: expanded ? '收起来源片段' : '展开来源片段',
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs2,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border.all(
                color: scheme.outline,
                width: AppElevation.borderWidthSm,
              ),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 固定 chevronDown + turns 旋转，取代硬切换图标：硬切换没有过渡，
                // 箭头会「跳」一下（与 AssistantReasoningDisclosure 同一处理）。
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: reducedMotionOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  child: Icon(
                    LucideIcons.chevronDown,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  source.materialName,
                  style: text.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(
              top: 4,
              left: 2,
              right: 8,
              bottom: 4,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                source.snippet,
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
