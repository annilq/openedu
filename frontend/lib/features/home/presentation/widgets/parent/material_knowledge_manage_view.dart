import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' show Dialog, showDialog;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_buttons.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_checkbox.dart';
import '../../../../../shared/widgets/app_dialog.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../providers/knowledge_manage_provider.dart';
import 'knowledge_point_scene_editor.dart';

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
      if (next.notice != null) {
        AppToast.show(context, next.notice!);
        ref.read(knowledgeManageProvider.notifier).consumeNotice();
      }
    });
    // 可删除条数：只有已落库（有 id）的行能删，骨架条目在 DB 里还不存在。
    final deletable = km.deletableSelectedCount;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 范围：知识点是家长私有的，必须锁死 (学科, 年级, 学期)。
          Row(
            children: [
              Expanded(
                child: AppPickerField<String>(
                  label: '学科',
                  values: const ['数学', '语文', '英语'],
                  labels: const ['数学', '语文', '英语'],
                  value: km.subject,
                  onChanged: (v) => notifier.setScope(v, km.grade, km.semester),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppPickerField<int>(
                  label: '年级',
                  values: List.generate(9, (i) => i + 1),
                  labels: List.generate(9, (i) => '${i + 1}年级'),
                  value: km.grade,
                  onChanged: (v) => notifier.setScope(km.subject, v, km.semester),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppPickerField<String>(
                  label: '学期',
                  // '' = 整学年/不限；其余为具体学期（与后端一致）。
                  values: const ['', '上学期', '下学期'],
                  labels: const ['整学年', '上学期', '下学期'],
                  value: km.semester,
                  onChanged: (v) => notifier.setScope(km.subject, km.grade, v),
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
                    AppCheckbox(
                      selected: selected,
                      semanticLabel: selected
                          ? '取消选择 ${kp.name}'
                          : '选择 ${kp.name}',
                      onTap: () => ref
                          .read(knowledgeManageProvider.notifier)
                          .toggle(kp.name),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(kp.name)),
                    const SizedBox(width: AppSpacing.sm),
                    // 「整学年」并集视图下同屏混着上/下学期的点，光看名字分不出
                    // 归属——学期徽标让教师点开前就知道这份讲解配给哪个学期。
                    // 限定了学期范围时后端只回该学期的行，徽标就是冗余信息，不画。
                    if (km.semester.isEmpty && kp.semester.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: AppTags.normal(kp.semester),
                      ),
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
                    if (kp.id != null)
                      AppTextAction(
                        label: '讲解',
                        onPressed: () async {
                          // 该知识点未配置交互讲解时，先提示去配置，避免编辑器
                          // 一律回退到同一默认模板，造成「每个点讲解都一样」的错觉。
                          final hasScenes =
                              kp.scenes != null && kp.scenes!.isNotEmpty;
                          if (!hasScenes) {
                            final configure = await AppDialog.confirm(
                              context,
                              title: const Text('尚未配置讲解资源'),
                              content: const Text(
                                '该知识点还没有交互讲解模板，是否现在去配置？',
                              ),
                              cancelLabel: '稍后',
                              confirmLabel: '去配置',
                            );
                            if (configure != true) return;
                          }
                          if (!context.mounted) return;
                          _openSceneEditor(
                            context,
                            kpId: kp.id!,
                            kpName: kp.name,
                            kpSemester: kp.semester,
                            subject: km.subject,
                            grade: km.grade,
                            scenes: kp.scenes,
                          );
                        },
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: AppSpacing.md),
            // 同一份勾选服务于两个动作：**确认转正**（把候选变成可统计的知识点）
            // 与**删除**（把这个范围里不再需要的候选清掉）。删除是破坏动作，走
            // 全站统一的 `error` 文字操作语言，并单独二次确认。
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                AppPrimaryButton(
                  label: km.selectedNames.isEmpty
                      ? '确认选中'
                      : '确认选中（${km.selectedNames.length}）',
                  fullWidth: false,
                  onPressed: km.selectedNames.isEmpty
                      ? null
                      : () => notifier.confirmSelected(),
                ),
                AppTextAction(
                  label: deletable == 0
                      ? '删除选中'
                      : '删除选中（$deletable）',
                  color: app.error,
                  semanticLabel: deletable == 0
                      ? '删除选中的知识点'
                      : '删除选中的 $deletable 个知识点',
                  onPressed:
                      deletable == 0 ? null : () => _confirmDelete(context, ref),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 删除前先确认：知识点没有回收站，删掉就是删掉了。
  ///
  /// 文案必须说清**什么不会被删**——已出的题与学情统计是按知识点**名字**快照存的，
  /// 删目录条目不会动它们；不清点这一点，家长会以为删了知识点历史就塌了。
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await AppDialog.confirm(
      context,
      title: const Text('删除知识点'),
      content: const Text(
        '确认删除选中的知识点？删除后出题时不会再出现它们。\n\n'
        '已经出过的题与学情记录不受影响，仍会按原知识点继续统计。',
      ),
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true) return;
    await ref.read(knowledgeManageProvider.notifier).deleteSelected();
  }

  /// 打开交互讲解编辑器（ADR-0061）：为已落库知识点编写默认交互讲解模板。
  ///
  /// 传**知识点自身的**学期（`kp.semester`）而非当前范围筛选值：范围可能是
  /// 「整学年」并集（此时同一屏混着上/下学期的点），弹窗要显示的是这份模板
  /// 实际作用的那个学期。
  void _openSceneEditor(
    BuildContext context, {
    required String kpId,
    required String kpName,
    required String kpSemester,
    required String subject,
    required int grade,
    required List<Map<String, dynamic>>? scenes,
  }) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: KnowledgePointSceneEditor(
              kpId: kpId,
              kpName: kpName,
              subject: subject,
              grade: grade,
              semester: kpSemester,
              initialScenes: scenes,
            ),
          ),
        ),
      ),
    );
  }
}
