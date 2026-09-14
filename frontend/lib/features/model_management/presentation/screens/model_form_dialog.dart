import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_chip.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../providers/models_notifier.dart';

/// 新增 / 编辑自定义模型的对话框（ShadDialog + 表单字段）。
///
/// 通过 [presets] 渲染「服务商」下拉（DeepSeek / OpenAI / Ollama ...），
/// 选中后自动带出 base_url 与模型名建议，大幅减少家长手动输入。
///
/// [initial] 为 null 表示新增；否则为编辑（id 用于 PUT）。保存成功后关闭并回调 [onDone]。
class ModelFormDialog extends ConsumerStatefulWidget {
  final ModelInfo? initial;
  final List<ModelProviderPreset> presets;
  final VoidCallback onDone;

  const ModelFormDialog({
    super.key,
    this.initial,
    required this.presets,
    required this.onDone,
  });

  @override
  ConsumerState<ModelFormDialog> createState() => _ModelFormDialogState();
}

class _ModelFormDialogState extends ConsumerState<ModelFormDialog> {
  final _labelCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _modelNameCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _providerCtrl = TextEditingController();
  bool _isDefault = false;
  bool _saving = false;

  /// 当前选中的服务商预设 key；null 表示未匹配到（手动模式）。
  String? _presetKey;

  ModelProviderPreset? get _preset {
    if (_presetKey == null) return null;
    for (final p in widget.presets) {
      if (p.key == _presetKey) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    if (m != null) {
      _labelCtrl.text = m.label;
      _baseUrlCtrl.text = m.baseUrl ?? '';
      _modelNameCtrl.text = m.modelName;
      _isDefault = m.isDefault;
      // 编辑时尝试把现有模型匹配到某个服务商预设，便于展示模型名建议。
      _presetKey = _matchPreset(m.provider, m.baseUrl);
    } else {
      // 新增默认选中第一个预设（若有），直接带出 base_url 与模型建议。
      _presetKey = widget.presets.isNotEmpty ? widget.presets.first.key : null;
      final first = widget.presets.isNotEmpty ? widget.presets.first : null;
      if (first != null) _baseUrlCtrl.text = first.baseUrl ?? '';
      _providerCtrl.text = widget.initial?.provider ?? (first?.provider ?? '');
    }
  }

  String? _matchPreset(String provider, String? baseUrl) {
    for (final p in widget.presets) {
      if (p.provider == provider &&
          (p.baseUrl ?? '') == (baseUrl ?? '')) {
        return p.key;
      }
    }
    return null;
  }

  void _onPresetChanged(String key) {
    final preset = widget.presets.firstWhere((p) => p.key == key);
    setState(() {
      _presetKey = key;
      // 选中服务商：自动带出默认 base_url（用户仍可手动改）。
      _baseUrlCtrl.text = preset.baseUrl ?? '';
    });
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelNameCtrl.dispose();
    _apiKeyCtrl.dispose();
    _providerCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final modelName = _modelNameCtrl.text.trim();
    if (label.isEmpty || modelName.isEmpty) {
      AppToast.show(context, '名称与模型名不能为空');
      return;
    }
    // provider 优先取所选服务商预设；无预设（手动模式）取手动填写值，再回退到编辑态/默认。
    final manualProvider = _providerCtrl.text.trim();
    final provider = _preset?.provider ??
        (manualProvider.isEmpty
            ? (widget.initial?.provider ?? 'openai_compat')
            : manualProvider);
    final baseUrl = _baseUrlCtrl.text.trim().isEmpty ? null : _baseUrlCtrl.text.trim();
    setState(() => _saving = true);
    final err = widget.initial == null
        ? await ref.read(modelsNotifierProvider.notifier).create(
              ModelCreateReq(
                label: label,
                provider: provider,
                baseUrl: baseUrl,
                modelName: modelName,
                apiKey: _apiKeyCtrl.text.isEmpty ? null : _apiKeyCtrl.text,
                isDefault: _isDefault,
                providerPreset: _presetKey,
              ),
            )
        : await ref.read(modelsNotifierProvider.notifier).update(
              widget.initial!.id,
              ModelUpdateReq(
                label: label,
                provider: provider,
                baseUrl: baseUrl,
                modelName: modelName,
                // 编辑时 api_key 留空表示不修改；非空则覆盖。
                apiKey: _apiKeyCtrl.text.isEmpty ? null : _apiKeyCtrl.text,
                isDefault: _isDefault,
                providerPreset: _presetKey,
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
    final hasPresets = widget.presets.isNotEmpty;
    final preset = _preset;
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
              if (hasPresets)
                AppPickerField<String>(
                  label: '服务商',
                  values: widget.presets.map((p) => p.key).toList(),
                  labels: widget.presets.map((p) => p.label).toList(),
                  value: _presetKey ?? widget.presets.first.key,
                  onChanged: _onPresetChanged,
                )
              else
                AppTextField(
                  label: '类型 (ollama / openai_compat)',
                  controller: _providerCtrl,
                  hintText: 'openai_compat',
                ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: '模型名（如 ${preset?.models.isNotEmpty == true ? preset!.models.first : 'gpt-4o / llama3'}）',
                controller: _modelNameCtrl,
                hintText: preset?.models.join(' / '),
              ),
              if (preset != null && preset.models.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                AppChipRow(
                  options: preset.models,
                  selected: {_modelNameCtrl.text},
                  onToggle: (name) => setState(() => _modelNameCtrl.text = name),
                ),
              ],
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
                hintText: widget.initial != null
                    ? '••••••••（不改请留空）'
                    : preset?.apiKeyHint,
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
