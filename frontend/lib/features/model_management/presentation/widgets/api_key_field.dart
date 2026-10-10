import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';

/// 模型编辑/新增表单里的 API Key 字段（与 [ModelFormDialog] 配套）。
///
/// 安全约束：明文密钥**绝不**回填到输入框（obscureText + 后端不回传明文），
/// 因此重开编辑框时该字段永远是空的——这会让用户误以为「密钥没保存 / 丢了」。
/// 为消除歧义，编辑态额外展示一行**非敏感**状态条：
///   - 已设置：shieldCheck + 「已设置密钥（明文不显示）」；
///   - 未设置：shieldAlert + 「尚未设置密钥」。
/// 提示文案也据此区分，明确「留空 = 不修改」。
class ApiKeyFormField extends StatelessWidget {
  final TextEditingController controller;
  final bool isEdit;
  final bool hasApiKey;
  final String? apiKeyHint;

  const ApiKeyFormField({
    super.key,
    required this.controller,
    required this.isEdit,
    required this.hasApiKey,
    this.apiKeyHint,
  });

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    final app = AppTheme.colorsOf(context);
    // 撞色板里没有 amber：未设置用 orange（纸底上比 yellow 更压得住），已设置用 green。
    final fg = hasApiKey ? AppBrutal.green : AppBrutal.orange;
    final statusText = isEdit
        ? (hasApiKey ? '已设置密钥（明文不显示）' : '尚未设置密钥')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (statusText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  hasApiKey ? LucideIcons.shieldCheck : LucideIcons.shieldAlert,
                  size: 14,
                  color: fg,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    statusText,
                    style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        AppTextField(
          label: isEdit ? 'API Key（留空=不修改）' : 'API Key',
          controller: controller,
          obscureText: true,
          hintText: isEdit
              ? (hasApiKey
                  ? '•••••••• 已设置，不改请留空'
                  : '必填：填入该服务的 API Key')
              : (apiKeyHint ?? '必填：填入该服务的 API Key'),
        ),
      ],
    );
  }
}
