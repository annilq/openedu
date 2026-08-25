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
    final focusedBorderColor = hasError ? app.error : app.primary;

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
          style: text.bodyLarge?.copyWith(
            color: widget.enabled ? app.onSurface : app.onSurfaceVariant,
          ),
          placeholder: widget.hintText == null
              ? null
              : Text(
                  widget.hintText!,
                  style: text.bodyLarge?.copyWith(color: app.onSurfaceVariant),
                ),
          cursorColor: app.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          leading: widget.prefixIcon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Icon(
                    widget.prefixIcon,
                    color: app.onSurfaceVariant,
                    size: 22,
                  ),
                ),
          trailing: widget.obscureText
              ? ShadButton.ghost(
                  width: 40,
                  height: 40,
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _obscured = !_obscured),
                  child: Icon(
                    _obscured ? LucideIcons.eye : LucideIcons.eyeOff,
                    color: app.onSurfaceVariant,
                    size: 20,
                  ),
                )
              : null,
          decoration: ShadDecoration(
            color: widget.enabled
                ? app.surfaceRaised
                : app.surfaceSunken,
            border: ShadBorder.all(
              color: borderColor,
              width: hasError ? 1.5 : 1,
              radius: BorderRadius.circular(AppRadius.input),
            ),
            focusedBorder: ShadBorder.all(
              color: focusedBorderColor,
              width: 1.5,
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
        ShadSelect<T>(
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
            color: app.surfaceRaised,
            border: ShadBorder.all(
              color: borderColor,
              width: hasError ? 1.5 : 1,
              radius: BorderRadius.circular(AppRadius.input),
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
