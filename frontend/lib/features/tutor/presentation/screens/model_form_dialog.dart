import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../providers/models_notifier.dart';

/// 新增 / 编辑自定义模型的对话框（ShadDialog + 表单字段）。
///
/// [initial] 为 null 表示新增；否则为编辑（id 用于 PUT）。保存成功后关闭并回调 [onDone]。
class ModelFormDialog extends ConsumerStatefulWidget {
  final ModelInfo? initial;
  final VoidCallback onDone;

  const ModelFormDialog({super.key, this.initial, required this.onDone});

  @override
  ConsumerState<ModelFormDialog> createState() => _ModelFormDialogState();
}

class _ModelFormDialogState extends ConsumerState<ModelFormDialog> {
  final _labelCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _modelNameCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  String _provider = 'ollama';
  bool _isDefault = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    if (m != null) {
      _labelCtrl.text = m.label;
      _baseUrlCtrl.text = m.baseUrl ?? '';
      _modelNameCtrl.text = m.modelName;
      _provider = m.provider;
      _isDefault = m.isDefault;
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelNameCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final modelName = _modelNameCtrl.text.trim();
    if (label.isEmpty || modelName.isEmpty) {
      AppToast.show(context, '名称与模型名不能为空');
      return;
    }
    setState(() => _saving = true);
    final err = widget.initial == null
        ? await ref.read(modelsNotifierProvider.notifier).create(
              ModelCreateReq(
                label: label,
                provider: _provider,
                baseUrl: _baseUrlCtrl.text.trim().isEmpty
                    ? null
                    : _baseUrlCtrl.text.trim(),
                modelName: modelName,
                apiKey: _apiKeyCtrl.text.isEmpty ? null : _apiKeyCtrl.text,
                isDefault: _isDefault,
              ),
            )
        : await ref.read(modelsNotifierProvider.notifier).update(
              widget.initial!.id,
              ModelUpdateReq(
                label: label,
                provider: _provider,
                baseUrl: _baseUrlCtrl.text.trim().isEmpty
                    ? null
                    : _baseUrlCtrl.text.trim(),
                modelName: modelName,
                // 编辑时 api_key 留空表示不修改；非空则覆盖。
                apiKey: _apiKeyCtrl.text.isEmpty ? null : _apiKeyCtrl.text,
                isDefault: _isDefault,
              ),
            );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      AppToast.error(context, err);
      return;
    }
    Navigator.of(context).pop();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return ShadDialog(
      closeIcon: const SizedBox.shrink(),
      title: Text(
        widget.initial == null ? '添加模型' : '编辑模型',
        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: text.labelMedium?.copyWith(color: app.onSurface)),
        ),
        ShadButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving ? '保存中…' : '保存',
            style: text.labelMedium?.copyWith(color: app.onPrimary),
          ),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(label: '名称', controller: _labelCtrl),
              const SizedBox(height: AppSpacing.md),
              AppPickerField<String>(
                label: '类型',
                values: const ['ollama', 'openai_compat'],
                labels: const ['Ollama（本地）', 'OpenAI 兼容'],
                value: _provider,
                onChanged: (v) => setState(() => _provider = v),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: '模型名（如 llama3 / gpt-4o）',
                controller: _modelNameCtrl,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Base URL（Ollama 留空用默认）',
                controller: _baseUrlCtrl,
                hintText: 'http://localhost:11434',
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'API Key（留空=不修改）',
                controller: _apiKeyCtrl,
                obscureText: true,
                hintText: widget.initial != null ? '••••••••（不改请留空）' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text('设为默认模型', style: text.titleSmall),
                  ),
                  ShadSwitch(
                    value: _isDefault,
                    checkedTrackColor: app.primary,
                    onChanged: (v) => setState(() => _isDefault = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
