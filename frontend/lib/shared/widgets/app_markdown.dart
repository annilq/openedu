import 'package:flutter/widgets.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../theme/app_theme.dart';

/// AI 气泡正文 Markdown 渲染（B-4，ADR-0036 单入口）。
///
/// 把设计令牌（[AppColors] / [AppText]）映成一套 gpt_markdown 样式表，
/// Parent/Child 双模式 + 亮暗下与全站排版一致。要点：
///
/// - 代码块复制按钮**关闭**（`CodeBlockStyle.showCopyButton: false`）——
///   沿用原生 [_CopyButton]（整条消息复制），不引入 Material 渲染栈
///   （根仍是 CupertinoApp，子树无 Material 祖先）。
/// - 基础正文走 `style`、组件级走 `styleSheet`，未设字段回落包默认，不会改坏既有排版。
/// - 流式：父级每帧用最新 `data` 重建，gpt_markdown 1.2 已缓存已定稿前缀，成本稳定。
class AppMarkdown extends StatelessWidget {
  final String data;
  final TextAlign textAlign;

  const AppMarkdown(
    this.data, {
    super.key,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final body = text.bodyMedium?.copyWith(
      color: scheme.onSurface,
      height: 1.55,
    );

    return GptMarkdown(
      data,
      textAlign: textAlign,
      style: body,
      styleSheet: GptMarkdownStyleSheet(
        heading: HeadingStyle(
          textStyle: text.titleMedium?.copyWith(color: scheme.onSurface),
        ),
        inlineCode: InlineCodeStyle(
          color: scheme.onSurface,
          backgroundColor: scheme.surfaceContainer,
          borderColor: scheme.outline,
          borderRadius: const Radius.circular(4),
        ),
        codeBlock: CodeBlockStyle(
          backgroundColor: scheme.surfaceContainer,
          borderColor: scheme.outline,
          textColor: scheme.onSurface,
          borderRadius: Radius.circular(AppRadius.card),
          showCopyButton: false,
        ),
        blockQuote: BlockQuoteStyle(
          barColor: scheme.primary,
          backgroundColor: scheme.surfaceContainer,
          barRadius: const Radius.circular(2),
          textStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        link: LinkStyle(
          color: scheme.primary,
          decoration: TextDecoration.underline,
        ),
        list: ListStyle(bulletColor: scheme.onSurfaceVariant),
        table: TableStyle(
          borderColor: scheme.outline,
          headerBackground: scheme.surfaceContainer,
          borderRadius: Radius.circular(AppRadius.card),
        ),
      ),
    );
  }
}
