import 'package:flutter/widgets.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../../shared/features/materials/domain/repositories/material_repository.dart';

/// 知识点溯源内容（ADR-0093）：列出命中该名字的源资料，并展开其片段原文，
/// 供教师核对「这个点确实出自教材哪一段」。
///
/// 知识点与资料无外键，数据源是 ``Material.knowledge_points`` 名字串反查得到。
/// 后端已在书内做段级词匹配：命中时只回密度最高的前 10 段（``matched=true``），
/// 一段都没命中才兜底全本（``matched=false``）——此时必须照实说明，不能把
/// 全本伪装成命中集。
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
          _SourceMaterialCard(src: src, kpName: kpName),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SourceMaterialCard extends StatefulWidget {
  const _SourceMaterialCard({required this.src, required this.kpName});

  final KnowledgePointSourceMaterial src;
  final String kpName;

  @override
  State<_SourceMaterialCard> createState() => _SourceMaterialCardState();
}

class _SourceMaterialCardState extends State<_SourceMaterialCard> {
  /// 兜底全本时首屏只铺 10 段，其余折叠——157 段平铺等于没铺。
  static const _previewLimit = 10;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final src = widget.src;
    final base = text.bodySmall ?? const TextStyle();
    final visible =
        _expanded ? src.chunks : src.chunks.take(_previewLimit).toList();
    final hidden = src.chunks.length - visible.length;
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
              AppTags.normal(src.matched
                  ? '命中 ${src.chunks.length} / 共 ${src.totalChunks} 段'
                  : '全文 ${src.totalChunks} 段'),
            ],
          ),
          if (!src.matched) ...[
            const SizedBox(height: 6),
            Text(
              '教材正文里没有出现「${widget.kpName}」的原词，'
              '可能是知识点提炼的措辞与教材不同；先给出全文，你可以直接翻看核对。',
              style: text.bodySmall?.copyWith(color: app.secondary),
            ),
          ],
          const SizedBox(height: 8),
          if (src.chunks.isEmpty)
            Text(
              '（该资料暂无切片文本）',
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
            )
          else
            for (final ch in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTags.normal('${ch.seq + 1}'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: _highlight(
                            _flatten(ch.content),
                            widget.kpName,
                            base,
                            base.copyWith(
                              color: app.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (hidden > 0) ...[
            const SizedBox(height: 4),
            AppTextAction(
              label: '展开其余 $hidden 段',
              onPressed: () => setState(() => _expanded = true),
            ),
          ],
        ],
      ),
    );
  }
}

/// PDF 直抽文本渲染前折叠空白：硬断行、缩进、连续空格在中文片段里只是噪声，
/// 折成流动文本才可读。不改库内存量，只改展示。
String _flatten(String content) => content.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 把片段里出现的知识点名高亮出来，教师一眼定位「这段就是讲这个的」。
///
/// 容差两点：名字里的 ASCII 字符同时接受全角孪生（相差 0xFEE0，教材 PDF 常抽
/// 成全角），任意两个字符之间容许正文插入空白——PDF 直抽的硬断行会把术语
/// 劈成两半（「加法\\n交换律」），不容空白就永远高亮不上。找不到就原样返回。
List<TextSpan> _highlight(
  String flattened,
  String term,
  TextStyle base,
  TextStyle mark,
) {
  final pattern = _termPattern(term);
  if (pattern == null) return [TextSpan(text: flattened, style: base)];
  final spans = <TextSpan>[];
  var start = 0;
  for (final m in pattern.allMatches(flattened)) {
    if (m.start > start) {
      spans.add(TextSpan(text: flattened.substring(start, m.start), style: base));
    }
    spans.add(TextSpan(text: m.group(0), style: mark));
    start = m.end;
  }
  if (start < flattened.length) {
    spans.add(TextSpan(text: flattened.substring(start), style: base));
  }
  return spans;
}

RegExp? _termPattern(String term) {
  if (term.trim().isEmpty) return null;
  final atoms = <String>[];
  for (final rune in term.runes) {
    final ch = String.fromCharCode(rune);
    if (RegExp(r'\s').hasMatch(ch)) {
      atoms.add(r'\s*');
    } else if (ch.codeUnitAt(0) >= 0x21 && ch.codeUnitAt(0) <= 0x7e) {
      final twin = String.fromCharCode(ch.codeUnitAt(0) + 0xfee0);
      atoms.add('[${RegExp.escape(ch)}${RegExp.escape(twin)}]');
    } else {
      atoms.add(RegExp.escape(ch));
    }
  }
  try {
    // 空白只容许落在字符之间：结尾挂 \s* 会把后面的空格吞进高亮段。
    return RegExp(atoms.join(r'\s*'));
  } on FormatException {
    return null;
  }
}
