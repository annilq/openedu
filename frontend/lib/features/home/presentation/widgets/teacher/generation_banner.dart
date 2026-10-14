import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../providers/home_notifier.dart';

/// 出题进行中的常驻指示条（跨 Tab），带停止按钮。
///
/// 挂在壳层而不是生成页：出题的 SSE 在 `taskGenNotifierProvider`（非 autoDispose）
/// 里跑，教师一旦走开，生成页就被卸载、进度条随之消失——回来也不知道出到哪儿了。
/// 这里跨 Tab 常驻，并带一个随时可点的停止按钮。
///
/// 从 `home_screen.dart` 抽出来（ADR-0058）：它是一块**纯渲染**，与「哪个页面在栈上」
/// 没有任何关系，挤在组合根里只会把导航接线淹没在 60 行布局代码里。
class GenerationBanner extends StatelessWidget {
  final TaskGenPreview state;
  final VoidCallback onStop;

  const GenerationBanner({super.key, required this.state, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    // 进度文案优先级：首题 STEP 前的阶段帧 > 当前题进度标签 > 兜底「生成中…」。
    final label = state.stage.isNotEmpty
        ? state.stage
        : state.liveLabel.isNotEmpty
            ? state.liveLabel
            : '生成中…';
    final count = state.expected > 0
        ? '已出 ${state.questions.length}/${state.expected} 题'
        : '已出 ${state.questions.length} 题';
    return Container(
      decoration: BoxDecoration(
        color: app.surfaceActive,
        border: Border(
          bottom: BorderSide(
            color: app.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.loaderCircle, size: 16, color: app.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: text.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(count,
                    style: text.labelSmall
                        ?.copyWith(color: app.onSurfaceVariant)),
              ],
            ),
          ),
          AppIconAction(
            icon: LucideIcons.x,
            semanticLabel: '停止生成',
            onPressed: onStop,
          ),
        ],
      ),
    );
  }
}
