import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../providers/models_notifier.dart';
import 'model_form_dialog.dart';

/// 家长端 AI 模型管理页（票据 08）：列出内置 + 自定义模型，支持增删改与设默认。
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
    showShadDialog(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => ModelFormDialog(
        initial: initial,
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
          AppSpacing.xl2, AppSpacing.md, AppSpacing.xl2, AppSpacing.xl4),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('AI 模型管理'),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '选择用于出题 / 答疑的模型。内置模型随系统提供；自定义模型（Ollama / OpenAI 兼容）仅你可见，密钥由后端加密存储。',
                style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('内置模型', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.md),
              if (state is ModelsLoaded) ...[
                ...state.resp.builtin.map(_builtinCard),
                if (state.resp.builtin.isEmpty)
                  _emptyHint('暂无内置模型'),
              ] else if (state is ModelsLoading) ...[
                const AppLoading(),
              ] else if (state is ModelsError) ...[
                _emptyHint('加载失败：${(state).message}'),
              ] else ...[
                _emptyHint('加载中…'),
              ],
              const SizedBox(height: AppSpacing.xl2),
              Row(
                children: [
                  Expanded(
                    child: Text('自定义模型',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  AppPrimaryButton(
                    label: '添加模型',
                    icon: LucideIcons.plus,
                    fullWidth: false,
                    onPressed: () => _openForm(context, null),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (state is ModelsLoaded) ...[
                if (state.resp.custom.isEmpty)
                  _emptyHint('还没有自定义模型，点「添加模型」接入本地 Ollama 或 OpenAI 兼容服务')
                else
                  ...state.resp.custom.map((m) => _customCard(context, m)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _builtinCard(ModelInfo m) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(LucideIcons.sparkles, size: 18, color: app.accent),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.label,
                      style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${m.modelName} · ${m.provider}',
                      style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
                ],
              ),
            ),
            AppTags.info('内置'),
          ],
        ),
      ),
    );
  }

  Widget _customCard(BuildContext context, ModelInfo m) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
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
                          style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                      if (m.isDefault) ...[
                        const SizedBox(width: AppSpacing.sm),
                        AppTags.success('默认'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                      '${m.modelName} · ${m.provider}${m.baseUrl != null ? ' · ${m.baseUrl}' : ''}',
                      style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: app.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text(msg,
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
    );
  }
}
