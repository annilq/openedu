import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// 流式推理实时文本面板（DRY 收敛点：首次出题 `/tasks/generate` 与重生成
/// `regenerate-stream` 共用同一渲染 seam）。
///
/// 渲染层退化为对 [reasoning] 的忠实映射：后端已增量下发 THINKING，
/// 前端无需自有定时器（原 ReasoningTypewriterWidget 的 Timer 与事件到达解耦，
/// 导致生成期 `_shown` 永不前进、题卡到达后全文闪现）。[streaming] 期间末尾挂 `▌`
/// 光标，表示仍在揭示；[reasoning] 为空（首个增量到达前）显示占位文案。
///
/// [index] 为可选题号（从 1 开始）；非空时左侧芯片显示「第 N 题 · 生成中」，
/// 为空时显示「生成中」。卡片/顶部已有题号场景传 null 即可。[label] 为右侧进度
/// 文案（如整卷重生成的「第 i/N 题」），可空。
///
/// 仅依赖 `flutter/widgets.dart`，可在 Material-free 的 ShadApp/CupertinoApp
/// widget 树中安全复用（不引入 Material 祖先假设）。
class StreamReasoningPanel extends StatelessWidget {
  final int? index;
  final String label;
  final String reasoning;
  final bool streaming;

  const StreamReasoningPanel({
    super.key,
    this.index,
    this.label = '',
    required this.reasoning,
    this.streaming = true,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final chipText = index != null ? '第 $index 题 · 生成中' : '生成中';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surface,
        borderRadius: BorderRadius.circular(AppRadius.bubble),
        // 显式写宽：`Border.all(color:)` 默认 1px，在卡片普遍 2px 的体系里偏细
        // （原写法正是踩了这个默认值）。
        border: Border.all(color: app.outline, width: AppElevation.borderWidth),
        // 生成中的面板是一张「浮在页面上的纸」——同色底 + 墨黑描边 + 无模糊硬阴影
        // 表达抬升；暗色模式无阴影（墨黑阴影在深底不可见）。
        boxShadow: app.brightness == Brightness.dark
            ? AppElevation.none
            : AppElevation.hard(app.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: app.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  // 标签类小色块一律 1.5px 墨黑描边（与学科 chip / 题号 chip 同口径）：
                  // 浅蓝容器底在纸底上对比不足，不描边则标签边界糊掉。
                  border: Border.all(
                    color: app.outline,
                    width: AppElevation.borderWidthSm,
                  ),
                ),
                child: Text(chipText,
                    style: text.labelSmall?.copyWith(
                        color: app.onPrimaryContainer,
                        fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (label.isNotEmpty)
                Expanded(
                  child: Text(
                    label,
                    style: text.labelSmall?.copyWith(color: app.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // 首个推理增量到达前给占位文案，避免面板内出现一段空白。
          if (reasoning.isEmpty)
            Text(
              '正在构思出题思路…',
              style: text.bodySmall?.copyWith(
                color: app.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            // 忠实映射：直接渲染已增量下发的推理全文，[streaming] 时挂光标。
            Text(
              reasoning + (streaming ? '▌' : ''),
              style: text.bodySmall?.copyWith(
                color: app.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
