import 'package:cupertino_ui/cupertino_ui.dart';

import '../theme/app_theme.dart';

/// 扁平化输入框（纯 Cupertino，替代 Material TextFormField）。
///
/// 自带 label、前缀图标、错误文案展示；不依赖 Material Form 校验，
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

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final hasError = widget.errorText != null;
    final borderColor = hasError ? app.error : app.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: widget.enabled
                ? app.surfaceContainerLow
                : app.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: borderColor, width: hasError ? 1.5 : 1),
          ),
          child: CupertinoTextField(
            controller: widget.controller,
            obscureText: _obscured,
            readOnly: !widget.enabled,
            keyboardType: widget.keyboardType,
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            style: text.bodyLarge?.copyWith(
              color: widget.enabled ? app.onSurface : app.onSurfaceVariant,
            ),
            placeholder: widget.hintText,
            placeholderStyle:
                text.bodyLarge?.copyWith(color: app.onSurfaceVariant),
            prefix: widget.prefixIcon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Icon(
                      widget.prefixIcon,
                      color: app.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
            suffix: widget.obscureText
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _obscured = !_obscured),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        _obscured
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        color: app.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                  )
                : null,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.input)),
            ),
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_circle,
                  size: 14, color: app.error),
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

/// 扁平化选择框（纯 Cupertino，替代 Material DropdownButtonFormField）。
///
/// 点击弹出 [CupertinoPicker] 底部面板；通用泛型 [T]。
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

  String get _currentLabel {
    final i = values.indexWhere((v) => v == value);
    return i >= 0 ? labels[i] : '';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final hasError = errorText != null;
    final borderColor = hasError ? app.error : app.outline;
    final current = value;
    final index = values.indexWhere((v) => v == current);
    final selectedIndex = index < 0 ? 0 : index;

    void pick() {
      showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) {
          return _PickerSheet<T>(
            values: values,
            labels: labels,
            initialIndex: selectedIndex,
            onChanged: onChanged,
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        GestureDetector(
          onTap: pick,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: app.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: borderColor, width: hasError ? 1.5 : 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _currentLabel,
                    style: text.bodyLarge?.copyWith(color: app.onSurface),
                  ),
                ),
                Icon(CupertinoIcons.chevron_up_chevron_down,
                    color: app.onSurfaceVariant, size: 18),
              ],
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            errorText!,
            style: text.bodySmall?.copyWith(color: app.error, height: 1.3),
          ),
        ],
      ],
    );
  }
}

class _PickerSheet<T> extends StatefulWidget {
  final List<T> values;
  final List<String> labels;
  final int initialIndex;
  final ValueChanged<T> onChanged;

  const _PickerSheet({
    required this.values,
    required this.labels,
    required this.initialIndex,
    required this.onChanged,
  });

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return CupertinoPicker(
      scrollController: FixedExtentScrollController(initialItem: _index),
      itemExtent: 44,
      onSelectedItemChanged: (i) => setState(() => _index = i),
      selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
        background: app.primaryContainer,
      ),
      children: [
        for (final l in widget.labels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l,
              textAlign: TextAlign.center,
              style: AppTheme.textOf(context).bodyMedium,
            ),
          ),
      ],
    );
  }
}