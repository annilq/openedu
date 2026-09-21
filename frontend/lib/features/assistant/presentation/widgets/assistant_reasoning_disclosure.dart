import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_focusable_action.dart';

/// 出题思路折叠块：默认收起（正题优先），点开看 AI 为什么出这道题（ADR-0017）。
///
/// 用折叠而非弹层：卡片在消息流里，弹层会打断阅读；也避免与 [CupertinoButton]
/// 的 sheet 依赖。收起态给一句提示，不隐藏「有思路可看」这件事。
class AssistantReasoningDisclosure extends StatefulWidget {
  final String reasoning;

  const AssistantReasoningDisclosure({super.key, required this.reasoning});

  @override
  State<AssistantReasoningDisclosure> createState() =>
      _AssistantReasoningDisclosureState();
}

class _AssistantReasoningDisclosureState
    extends State<AssistantReasoningDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 不用 InkWell：App 根是 CupertinoApp/ShadApp，子树无 Material 祖先。
        // 也不留裸 GestureDetector——它不进焦点树，桌面端 Tab 跳不过来、Enter
        // 点不动，而 `flutter analyze` 照不出来（ADR-0046）。标题文字本身可读，
        // 故不另传 semanticLabel。
        AppFocusableAction(
          onTap: () => setState(() => _open = !_open),
          hoverHighlight: true,
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '出题思路',
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              // 固定 chevronDown + turns 旋转，取代原先 `_open ? chevronUp :
              // chevronDown` 的硬切换：硬切换没有过渡，箭头会「跳」一下。
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: _openDuration(context),
                child: Icon(LucideIcons.chevronDown,
                    size: 14, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // 展开/收起走高度过渡，不再是 `if (_open)` 的瞬时增删。
        AnimatedSize(
          duration: _openDuration(context),
          curve: AppCurves.state,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: scheme.surfaceSunken,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Text(
                      widget.reasoning,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// 折叠过渡时长：隐式动画**不自动尊重** reduce-motion，必须显式归零（ADR-0044）。
Duration _openDuration(BuildContext context) =>
    reducedMotionOf(context) ? Duration.zero : AppMotion.state;
