import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';

/// 扁平化输入框（基于 ShadInput，替代 CupertinoTextField）。
///
/// 自带 label、前缀图标、错误文案展示；不依赖 Form 校验，
/// 由业务侧通过 [errorText] 手动反馈错误。
class AppTextField extends StatefulWidget {
  final String label;
  final String? hintText;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.errorText,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final hasError = widget.errorText != null;
    final borderColor = hasError ? app.error : app.outline;
    final focusedBorderColor = hasError ? app.error : app.accent;
    final inputStyle = text.bodyLarge?.copyWith(
      color: widget.enabled ? app.onSurface : app.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        ShadInput(
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          style: inputStyle,
          // shadcn 的 EditableText 默认 textAlignVertical=top，文字落在编辑盒顶端
          // （compact 偏上 ~2.8px、child 模式偏上 ~8.7px）。用 forceStrutHeight 把
          // 行高强制撑满编辑盒（controlH - 4），Flutter 半行距使字形上下均分 → 居中。
          strutStyle: AppControl.inputStrut(context, inputStyle),
          placeholder: widget.hintText == null
              ? null
              : Text(
                  widget.hintText!,
                  style: text.bodyLarge?.copyWith(color: app.onSurfaceVariant),
                ),
          cursorColor: app.accent,
          // tight 约束钉死到控件高度，与按钮严格同高（零竖向 padding）。
          constraints: AppControl.inputConstraintsOf(context),
          padding: AppControl.inputPadding,
          leading: widget.prefixIcon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    widget.prefixIcon,
                    color: app.onSurfaceVariant,
                    size: 18,
                  ),
                ),
          trailing: widget.obscureText
              ? SizedBox(
                  // 眼睛切换按钮：用 heightSm（比 tight 32 的输入矮一档 = 28），
                  // 直接钉死盒尺寸，避免 shadcn ShadButton 内部 padding / 尺寸膨胀
                  // 把 28 顶成 32+ 撑爆 BoxyColumn。命中区用 GestureDetector 包裹
                  // Icon（与 AppCard 同套路：无 Material 依赖、尺寸确定）。
                  width: AppControl.heightSmOf(context),
                  height: AppControl.heightSmOf(context),
                  child: GestureDetector(
                    onTap: () => setState(() => _obscured = !_obscured),
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Icon(
                        _obscured ? LucideIcons.eye : LucideIcons.eyeOff,
                        color: app.onSurfaceVariant,
                        size: 18,
                      ),
                    ),
                  ),
                )
              : null,
          decoration: ShadDecoration(
            disableSecondaryBorder: true,
            color: widget.enabled
                ? app.surfaceRaised
                : app.surfaceSunken,
            border: ShadBorder.all(
              color: borderColor,
              width: 1,
              radius: BorderRadius.circular(AppRadius.input),
            ),
            focusedBorder: ShadBorder.all(
              color: focusedBorderColor,
              width: 1,
              radius: BorderRadius.circular(AppRadius.input),
            ),
          ),
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(LucideIcons.alertCircle, size: 14, color: app.error),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.errorText!,
                  style: text.bodySmall?.copyWith(
                    color: app.error,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 扁平化选择框（基于 ShadSelect，替代 CupertinoPicker 底部面板）。
///
/// 点击展开下拉选项；通用泛型 [T]。
class AppPickerField<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final List<String> labels;
  final T value;
  final ValueChanged<T> onChanged;
  final String? errorText;

  const AppPickerField({
    super.key,
    required this.label,
    required this.values,
    required this.labels,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final hasError = errorText != null;
    final borderColor = hasError ? app.error : app.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        // ShadSelectTheme 没有 constraints/minHeight 字段，只能在外部钉高：
        // 不钉的话下拉触发器高度由「文字行高 + padding」撑出，与按钮差 2~3px。
        ConstrainedBox(
          constraints: AppControl.inputConstraintsOf(context),
          child: ShadSelect<T>(
            initialValue: value,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            selectedOptionBuilder: (context, selected) {
              final i = values.indexOf(selected);
              return Text(
                i >= 0 ? labels[i] : '',
                style: text.bodyLarge?.copyWith(color: app.onSurface),
              );
            },
            options: [
              for (var i = 0; i < values.length; i++)
                ShadOption<T>(
                  value: values[i],
                  child: Text(
                    labels[i],
                    style: text.bodyLarge?.copyWith(color: app.onSurface),
                  ),
                ),
            ],
            placeholder: Text(
              '请选择',
              style: text.bodyLarge?.copyWith(color: app.onSurfaceVariant),
            ),
            decoration: ShadDecoration(
              disableSecondaryBorder: true,
              color: app.surfaceRaised,
              border: ShadBorder.all(
                color: borderColor,
                width: 1,
                radius: BorderRadius.circular(AppRadius.input),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(LucideIcons.alertCircle, size: 14, color: app.error),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  errorText!,
                  style: text.bodySmall?.copyWith(
                    color: app.error,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
