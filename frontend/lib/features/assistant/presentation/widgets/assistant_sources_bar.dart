import 'package:flutter/material.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../domain/assistant_source.dart';

/// 答疑答案下方的「参考来源」条：把本次命中并注入 prompt 的资料片段溯源列出来，
/// 直接回答「这条回答引用了资料库里的哪些内容」（ADR-0055 §13 引用透明）。
///
/// 单份资料可能命中多个片段：按 `materialId` 去重，片段拼接展示。点击资料名可展开
/// 看实际注入的片段摘要（清洗后的 snippet），让家长 / 学生核对出处。
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
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs2,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border.all(color: scheme.outline),
              borderRadius: BorderRadius.circular(AppSpacing.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: scheme.onSurfaceVariant,
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
