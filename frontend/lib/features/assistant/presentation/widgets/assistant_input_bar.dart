import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_content_frame.dart';

/// 助手底部输入栏：多行问题输入 + 发送（ADR-0036 单入口的唯一输入区）。
///
/// 从 [AssistantChatPage] 里拆出来（ADR-0058 §1：一个文件只暴露一个公开物）——
/// 该页原本 557 行、已登记在文件规模棘轮基线里，语音输入（ADR-0063）要往输入区加
/// 麦按钮与录音态状态，直接堆进页面会把基线推得更高。拆出来后语音相关的状态与
/// 控件都长在本文件里，主页面不新增一个字段。
///
/// 旧的「相关知识点（选填）」输入框已删除——它对应的字段没进请求体，是死 UI。
class AssistantInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const AssistantInputBar({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return SafeArea(
      top: false,
      // 与消息列表同宽同轴：助手整页可能 push 在壳外（家长端），不套上限的话大屏下
      // 输入框会横贯全屏、气泡却收在中间一列。
      child: AppContentFrame(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ShadInput(
                  controller: controller,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 4,
                  style: text.bodyLarge?.copyWith(color: scheme.onSurface),
                  placeholder: Text('输入你的学习问题…',
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  cursorColor: scheme.primary,
                  // 单行高度取「主行动档」，与右侧发送按钮同档：两者是同一组
                  // 控件，必须同高。此前输入框靠 `vertical: 14` 撑到 51px、按钮
                  // 硬编码 52、再用 `Padding(bottom: 2)` 手工找平——三个魔数互相
                  // 追着补。现在高度由同一令牌决定，竖向 padding 只负责多行时的
                  // 呼吸感（8+单行+8 = 37 < 48，单行仍是精确的 48，多行按内容增高）。
                  constraints: BoxConstraints(
                      minHeight: AppControl.heightLgOf(context)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(LucideIcons.pencil,
                        color: scheme.onSurfaceVariant, size: 20),
                  ),
                  decoration: ShadDecoration(
                    disableSecondaryBorder: true,
                    color: scheme.surfaceContainerLow,
                    border: ShadBorder.all(
                      color: scheme.outline,
                      width: 1,
                      radius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AppPrimaryButton(
                label: '发送',
                icon: LucideIcons.send,
                loadingLabel: '思考中',
                loading: sending,
                onPressed: onSend,
                height: AppControl.heightLgOf(context),
                fullWidth: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
