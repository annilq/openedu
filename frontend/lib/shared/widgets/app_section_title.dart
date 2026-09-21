import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// 章节标题：左侧 4px 墨黑色条 + 标题文字（ADR-0044：色条从 3px 靛蓝改为 4px 墨黑，
/// 与描边语言统一；标题色在撞色环境里承担「锚点」，不再与学科色抢色相）
/// 规范章节节奏（统一间距事实源，ADR 设计系统约束）：
/// - top    = [AppSpacing.sm] (8)：标题上沿留白；相邻 section 靠「上标题 bottom(8)
///   + 下标题 top(8)」叠加成 16px 统一间隔，页面无需再手动加 SizedBox。
/// - bottom = [AppSpacing.sm] (8)：标题 → 内容的统一间隔。
/// - 水平 0：标题左缘与全宽卡片（AppCard）左缘对齐；页面不要再给卡片套
///   `Padding(horizontal: lg)`，否则会与标题错位 ~12px。
/// 所有家长/设置页共用此节奏，确保跨页面 UI 一致。
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding =
        const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.sm),
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final style = AppTheme.textOf(context).titleMedium;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: app.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(child: Text(text, style: style)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
