import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_chip.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../domain/model_requests.dart';
import '../providers/models_notifier.dart';
import '../../../../shared/widgets/app_buttons.dart';

/// 新增 / 编辑模型的对话框（ShadDialog + 表单字段）。
///
/// 通过 [presets] 渲染「服务商」下拉（DeepSeek / OpenAI / Ollama ...），
/// 选中后自动带出 base_url 与模型名建议，大幅减少家长手动输入。
///
/// [initial] 为 null 表示新增；否则为编辑（id 用于 PUT）。保存成功后关闭并回调 [onDone]。
/// ADR-0039：新增时 API Key 必填（本地前置拦截 + 后端强制）；编辑留空 = 不修改。
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
  bool _probing = false;
  ModelProbeResult? _probe;

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
    // 任一字段被改动后，上一次的测试结论即失效——留着「连接成功」的绿灯再改密钥，
    // 正是本功能要消灭的那种假象。
    for (final c in <TextEditingController>[
      _labelCtrl,
      _baseUrlCtrl,
      _modelNameCtrl,
      _apiKeyCtrl,
      _providerCtrl,
    ]) {
      c.addListener(_invalidateProbe);
    }
  }

  void _invalidateProbe() {
    if (_probe != null && mounted) setState(() => _probe = null);
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

  /// 表单当前值 → 一组模型参数。
  ///
  /// 保存与「测试连接」**共用**这一个出口：provider 的回落逻辑（预设 > 手填 >
  /// 编辑态 > openai_compat）若在两处各写一遍，迟早试的是 A、存的是 B。
  ({
    String label,
    String provider,
    String? baseUrl,
    String modelName,
    String apiKey,
  }) _formParams() {
    final manualProvider = _providerCtrl.text.trim();
    final baseUrl = _baseUrlCtrl.text.trim();
    return (
      label: _labelCtrl.text.trim(),
      provider: _preset?.provider ??
          (manualProvider.isEmpty
              ? (widget.initial?.provider ?? 'openai_compat')
              : manualProvider),
      baseUrl: baseUrl.isEmpty ? null : baseUrl,
      modelName: _modelNameCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
    );
  }

  /// 「测试连接」：拿表单里（可能尚未保存的）参数去后端真发一次请求。
  ///
  /// 走后端而不是前端直连厂商——密钥密文只在后端，编辑时密钥留空更是只有后端
  /// 才知道该用哪一份去试。结果一律以 [ModelProbeResult] 呈现（连不上也是 200）。
  Future<void> _testConnection() async {
    final p = _formParams();
    if (p.modelName.isEmpty) {
      AppToast.show(context, '请先填写模型名');
      return;
    }
    // 编辑态留空 = 沿用库里那份密钥（后端据此解密）；新增态则必须先填。
    if (widget.initial == null && p.apiKey.isEmpty) {
      AppToast.show(context, '请先填写 API Key');
      return;
    }
    setState(() {
      _probing = true;
      _probe = null;
    });
    final result = await ref
        .read(modelsNotifierProvider.notifier)
        .testConnection(
          ModelProbeReq(
            modelId: widget.initial?.id,
            provider: p.provider,
            baseUrl: p.baseUrl,
            modelName: p.modelName,
            apiKey: p.apiKey.isEmpty ? null : p.apiKey,
            providerPreset: _presetKey,
          ),
        );
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probe = result;
    });
  }

  Future<void> _save() async {
    final p = _formParams();
    if (p.label.isEmpty || p.modelName.isEmpty) {
      AppToast.show(context, '名称与模型名不能为空');
      return;
    }
    // ADR-0039：新增必须带 API Key（后端也强制校验，这里前置拦截以免白跑一趟）；
    // 编辑留空 = 不修改已有密钥，故仅在新增时必填。
    if (widget.initial == null && p.apiKey.isEmpty) {
      AppToast.show(context, '请填写 API Key');
      return;
    }
    setState(() => _saving = true);
    final err = widget.initial == null
        ? await ref.read(modelsNotifierProvider.notifier).create(
              ModelCreateReq(
                label: p.label,
                provider: p.provider,
                baseUrl: p.baseUrl,
                modelName: p.modelName,
                apiKey: p.apiKey,
                isDefault: _isDefault,
                providerPreset: _presetKey,
              ),
            )
        : await ref.read(modelsNotifierProvider.notifier).update(
              widget.initial!.id,
              ModelUpdateReq(
                label: p.label,
                provider: p.provider,
                baseUrl: p.baseUrl,
                modelName: p.modelName,
                // 编辑时 api_key 留空表示不修改；非空则覆盖。
                apiKey: p.apiKey.isEmpty ? null : p.apiKey,
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

  /// 测试结果条：撞色填充 + 墨黑描边（ADR-0044），前景走 [AppBrutal.onColor]
  /// ——亮块配墨黑、深块配白，不得自配色。
  Widget _probeStrip(BuildContext context, ModelProbeResult r) {
    final text = AppTheme.textOf(context);
    final fill = r.ok ? AppBrutal.green : AppBrutal.red;
    final fg = AppBrutal.onColor(fill);
    final detail = r.detail;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppBrutal.ink, width: AppElevation.borderWidth),
        boxShadow: AppElevation.hard(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            r.ok ? LucideIcons.checkCircle2 : LucideIcons.alertTriangle,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              detail == null || detail.isEmpty ? r.message : '${r.message}\n$detail',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: fg, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final hasPresets = widget.presets.isNotEmpty;
    final preset = _preset;
    return ShadDialog(
      closeIcon: const SizedBox.shrink(),
      constraints: const BoxConstraints(maxWidth: AppLayout.dialogForm),
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
      child: PopIn(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.dialogForm),
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
                  // _presetKey 为 null 表示现有模型的 provider+baseUrl 匹配不到任何预设
                  // （自定义服务商）——置空显示占位，而不是硬选第一个预设（会误导家长）。
                  value: _presetKey,
                  placeholder: '自定义（未匹配预设）',
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
                label: widget.initial == null ? 'API Key' : 'API Key（留空=不修改）',
                controller: _apiKeyCtrl,
                obscureText: true,
                hintText: widget.initial != null
                    ? '••••••••（不改请留空）'
                    : (preset?.apiKeyHint ?? '必填：填入该服务的 API Key'),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  AppBrutalButton(
                    label: _probing ? '测试中…' : '测试连接',
                    icon: LucideIcons.plug,
                    fill: AppBrutal.cyan,
                    fullWidth: false,
                    onPressed: _probing ? null : _testConnection,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '真实调用一次：收到首个响应即结束，用于确认密钥、地址与模型名都对。',
                      style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              if (_probe != null) ...[
                const SizedBox(height: AppSpacing.md),
                _probeStrip(context, _probe!),
              ],
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
      ),
    );
  }
}
