import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../providers/models_notifier.dart';
import 'model_form_dialog.dart';

/// 家长端 AI 模型管理页：列出、增删改本家长录入的模型，并支持设默认。
///
/// ADR-0039：不再有「内置模型」，所有模型都必须手动添加（新增时 api_key 必填）。
/// 仅家长可见；api_key 由后端加密存储，前端不回显明文。
class ParentModelManagementScreen extends ConsumerStatefulWidget {
  const ParentModelManagementScreen({super.key});

  @override
  ConsumerState<ParentModelManagementScreen> createState() =>
      _ParentModelManagementScreenState();
}

class _ParentModelManagementScreenState
    extends ConsumerState<ParentModelManagementScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(modelsNotifierProvider.notifier).load(),
    );
  }

  void _openForm(BuildContext context, ModelInfo? initial) {
    final s = ref.read(modelsNotifierProvider);
    final providers =
        s is ModelsLoaded ? s.providers : const <ModelProviderPreset>[];
    showShadDialog(
      context: context,
      barrierColor: AppTheme.colorsOf(context).scrim,
      builder: (_) => ModelFormDialog(
        initial: initial,
        presets: providers,
        onDone: () => AppToast.show(context, '已保存'),
      ),
    );
  }

  Future<void> _confirmDelete(ModelInfo m) async {
    final ok = await AppDialog.confirm(
      context,
      title: const Text('删除模型'),
      content: Text('确定删除「${m.label}」？该操作不可撤销。'),
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true) return;
    final err = await ref.read(modelsNotifierProvider.notifier).delete(m.id);
    if (!mounted) return;
    _reportModelError(err);
  }

  /// 用 State 自身的 context 同步弹错误提示（避免跨 await 的 context 安全 lint）。
  void _reportModelError(String? err) {
    if (err != null) AppToast.error(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(modelsNotifierProvider);
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl2),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('AI 模型管理'),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '选择用于出题 / 答疑的模型。模型需你手动添加（DeepSeek / Ollama / OpenAI 兼容），'
                '添加时必须填写 API Key，密钥由后端加密存储、仅你可见。',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionTitle(
                '我的模型',
                trailing: AppPrimaryButton(
                  label: '添加模型',
                  icon: LucideIcons.plus,
                  fullWidth: false,
                  onPressed: () => _openForm(context, null),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (state is ModelsLoaded) ...[
                if (state.resp.custom.isEmpty)
                  _emptyHint('还没有模型，点「添加模型」接入 DeepSeek、本地 Ollama 或其他 OpenAI 兼容服务')
                else
                  ...state.resp.custom.map((m) => _modelCard(context, m)),
              ] else if (state is ModelsLoading) ...[
                const AppLoading(),
              ] else if (state is ModelsError) ...[
                _emptyHint('加载失败：${(state).message}'),
              ] else ...[
                _emptyHint('加载中…'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _modelCard(BuildContext context, ModelInfo m) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(LucideIcons.box, size: 18, color: app.accent),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(m.label,
                          style: text.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (m.isDefault) ...[
                        const SizedBox(width: AppSpacing.sm),
                        AppTags.success('默认'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                      '${m.modelName} · ${m.provider}${m.baseUrl != null ? ' · ${m.baseUrl}' : ''}',
                      style: text.bodySmall
                          ?.copyWith(color: app.onSurfaceVariant)),
                ],
              ),
            ),
            if (!m.isDefault)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () async {
                  final err = await ref
                      .read(modelsNotifierProvider.notifier)
                      .setDefault(m.id);
                  if (!mounted) return;
                  _reportModelError(err);
                },
                child: const Text('设为默认'),
              ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _openForm(context, m),
              child: const Text('编辑'),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _confirmDelete(m),
              child: Text('删除', style: TextStyle(color: app.error)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyHint(String msg) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(msg,
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
    );
  }
}
