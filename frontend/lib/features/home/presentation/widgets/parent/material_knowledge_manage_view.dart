import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_buttons.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../providers/knowledge_manage_provider.dart';

/// 知识点管理视图（ADR-0055 §4 确认页）：按 (学科, 年级) 列出知识点目录，
/// 勾选待审 / 骨架条目并批量确认转正。从资料库页分段切换进来。
///
/// [km.items] 元素的静态类型来自 [knowledgeManageProvider] 暴露的
/// [KnowledgeManageState]，本文件不显式 import `data/` 层（R4）。
class MaterialKnowledgeManageView extends ConsumerStatefulWidget {
  const MaterialKnowledgeManageView({super.key});

  @override
  ConsumerState<MaterialKnowledgeManageView> createState() =>
      _MaterialKnowledgeManageViewState();
}

class _MaterialKnowledgeManageViewState
    extends ConsumerState<MaterialKnowledgeManageView> {
  @override
  Widget build(BuildContext context) {
    final km = ref.watch(knowledgeManageProvider);
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final notifier = ref.read(knowledgeManageProvider.notifier);
    ref.listen(knowledgeManageProvider, (_, next) {
      if (next.notice != null) AppToast.show(context, next.notice!);
      ref.read(knowledgeManageProvider.notifier).consumeNotice();
    });

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 范围：知识点是家长私有的，必须锁死 (学科, 年级)。
          Row(
            children: [
              Expanded(
                child: AppPickerField<String>(
                  label: '学科',
                  values: const ['数学', '语文', '英语'],
                  labels: const ['数学', '语文', '英语'],
                  value: km.subject,
                  onChanged: (v) => notifier.setScope(v, km.grade),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppPickerField<int>(
                  label: '年级',
                  values: List.generate(9, (i) => i + 1),
                  labels: List.generate(9, (i) => '${i + 1}年级'),
                  value: km.grade,
                  onChanged: (v) => notifier.setScope(km.subject, v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (km.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                '${km.pendingCount} 个待审知识点（确认后参与掌握度统计）',
                style: text.bodySmall?.copyWith(color: app.secondary),
              ),
            ),
          if (km.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(km.error!,
                  style: text.bodySmall?.copyWith(color: app.error)),
            ),
          if (km.loading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: AppLoading()),
            )
          else if (km.items.isEmpty)
            const AppEmptyState(
              icon: LucideIcons.tags,
              title: '该范围暂无知识点',
              message: '上传并向量化资料后，AI 会从中涌现知识点',
            )
          else ...[
            ...km.items.map((kp) {
              // kp 静态类型由 KnowledgeManageState.items 提供；在此闭包内
              // 访问 .name/.status/.id 不触发 dynamic 告警，也无需 import data 层。
              final selected = km.selectedNames.contains(kp.name);
              // 状态徽标：待审（secondary）/ 已转正（primary）/ 骨架（灰，id 为 null）。
              final (label, color) = switch (kp.status) {
                'pending' => ('待审', app.secondary),
                'curated' => (kp.id == null
                    ? ('骨架', app.onSurfaceVariant)
                    : ('已转正', app.primary)),
                _ => ('', app.onSurfaceVariant),
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    _checkBox(
                      selected,
                      () => ref
                          .read(knowledgeManageProvider.notifier)
                          .toggle(kp.name),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(kp.name)),
                    const SizedBox(width: AppSpacing.sm),
                    if (label.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          border: Border.all(color: color, width: 1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          style: text.bodySmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: AppSpacing.md),
            AppPrimaryButton(
              label: km.selectedNames.isEmpty
                  ? '确认选中'
                  : '确认选中（${km.selectedNames.length}）',
              onPressed: km.selectedNames.isEmpty
                  ? null
                  : () => notifier.confirmSelected(),
            ),
          ],
        ],
      ),
    );
  }

  /// 可点击勾选框（neo-brutalist：明确描边，不依赖三方 checkbox 样式）。
  Widget _checkBox(bool selected, VoidCallback onTap) {
    final app = AppTheme.colorsOf(context);
    return AppFocusableAction(
      onTap: onTap,
      semanticLabel: selected ? '取消选择' : '选择',
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: selected ? app.primary : app.surfaceRaised,
          border: Border.all(color: app.outline, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: selected
            ? Center(
                child: Icon(LucideIcons.check, size: 14, color: app.onPrimary))
            : null,
      ),
    );
  }
}
