import 'package:flutter/widgets.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../../shared/features/materials/domain/repositories/material_repository.dart';

/// 知识点溯源内容（ADR-0093）：列出命中该名字的源资料，并展开其片段原文，
/// 供教师核对「这个点确实出自教材哪一段」。
///
/// 知识点与资料无外键，数据源是 ``Material.knowledge_points`` 名字串反查得到，
/// 片段即该资料的整篇切片；``MaterialChunk.knowledge_point`` 字段当前未赋值、
/// 不参与溯源。
class KnowledgePointSourceView extends StatelessWidget {
  const KnowledgePointSourceView({
    super.key,
    required this.kpName,
    required this.sources,
  });

  final String kpName;
  final List<KnowledgePointSourceMaterial> sources;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    if (sources.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '没有资料引用「$kpName」。该知识点应是由教材涌现而来，'
          '若此处为空可能是元数据未提取。',
          style: text.bodyMedium?.copyWith(color: app.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '共 ${sources.length} 份来源资料，展开可核对原始片段：',
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final src in sources) ...[
          _SourceMaterialCard(src: src),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SourceMaterialCard extends StatelessWidget {
  const _SourceMaterialCard({required this.src});

  final KnowledgePointSourceMaterial src;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(src.materialName, style: text.labelMedium),
              ),
              AppTags.normal('${src.chunks.length} 段'),
            ],
          ),
          const SizedBox(height: 8),
          if (src.chunks.isEmpty)
            Text(
              '（该资料暂无切片文本）',
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
            )
          else
            for (final ch in src.chunks)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTags.normal('${ch.seq + 1}'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(ch.content, style: text.bodySmall),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
