import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:kids_learn/shared/features/materials/providers/material_providers.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_buttons.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_dialog.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../providers/knowledge_manage_provider.dart';
import '../../../../courseware/presentation/pages/courseware_editor_page.dart';
import 'package:kids_learn/features/courseware/presentation/widgets/courseware_recent_bar.dart';
import 'knowledge_point_row.dart';
import 'knowledge_point_source_view.dart';

/// 知识点管理视图（ADR-0055 §4 确认页 / ADR-0066 范围来自教材）：
/// 按 (学科, 年级, 学期) 列出知识点目录，
/// 勾选待审知识点并批量确认转正。从资料库页分段切换进来。
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
  void initState() {
    super.initState();
    // 入口先拉「传过教材的范围」：下拉由它派生，范围清单为空时整页走空态。
    Future.microtask(
      () => ref.read(knowledgeManageProvider.notifier).loadScopes(),
    );
  }

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
    // 可删除条数：只有已落库（有 id）的行能删。
    final deletable = km.deletableSelectedCount;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 一份教材都还没传：整个页面就是一句「去上传」，下拉一个都不给——
          // 摆出 9 年级 × 3 学科的空门只会让人挨个试。
          if (km.scopes.isEmpty && !km.loading)
            AppEmptyState(
              icon: LucideIcons.tags,
              title: '还没有知识点来源',
              message: '知识点来自你上传的教材：到「备课资料」上传并完成提取后，'
                  '这里会按教材所在的范围列出知识点。',
            )
          else ...[
            const CoursewareRecentBar(),
            _ScopeBar(km: km),
            if (km.unscopedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  '有 ${km.unscopedCount} 份教材没识别出学科或年级，暂时归不到上面的范围；'
                  '到「备课资料」对它们点「重新提取」即可。',
                  style: text.bodySmall?.copyWith(color: app.secondary),
                ),
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
          // 审核覆盖度（ADR-0093）：已确认 / 总数，进度条直观展示审核进度。
          // 定义见 spec：覆盖度 = curated / total（审核口径），教材章节级覆盖度
          // 需解析教材目录，超出本次范围。
          if (km.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _CoverageMeter(
                total: km.items.length,
                curated: km.items
                    .where((e) => e.status == 'curated')
                    .length,
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
            // 空列表的**原因**由后端 notice 给出（没传教材 / 传了但没识别出知识点
            // 是两种截然不同的下一步），这里只做兜底文案。
            AppEmptyState(
              icon: LucideIcons.tags,
              title: '该范围暂无知识点',
              message: km.notice?.isNotEmpty == true
                  ? km.notice!
                  : '这份教材还没识别出知识点',
            )
          else ...[
            ...km.items.map((kp) => KnowledgePointRow(
              kp: kp,
              km: km,
              onOpenCourseware: _openCourseware,
              onOpenSource: (k) => _openSource(context, ref, k),
            )),
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
        ],
      ),
    );
  }

  /// 删除前先确认：知识点没有回收站，删掉就是删掉了。
  ///
  /// 文案必须说清**什么不会被删**——已出的题与学情统计是按知识点**名字**快照存的，
  /// 删目录条目不会动它们；不清点这一点，教师会以为删了知识点历史就塌了。
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

  /// 打开课件编辑器（ADR-0067 §3.8）：从知识点行出发，进入该知识点的课件备课 / 演示。
  ///
  /// 编辑器自己决定「已有则打开、没有则停在空态由用户新建」，这里只负责导航。
  void _openCourseware(dynamic kp) {
    if (kp.id == null) return;
    final km = ref.read(knowledgeManageProvider);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoursewareEditorPage(
          knowledgePointId: kp.id!,
          kpName: kp.name,
          subject: km.subject,
          grade: km.grade,
          semester: kp.semester,
        ),
      ),
    );
  }

  /// 溯源（ADR-0093）：拉取该名字在 (学科, 年级) 内命中的源资料 + 片段，弹窗核对出处。
  Future<void> _openSource(
    BuildContext context,
    WidgetRef ref,
    dynamic kp,
  ) async {
    final scope = ref.read(knowledgeManageProvider);
    final sources = await ref
        .read(materialRepositoryProvider)
        .getKnowledgePointSources(
          subject: scope.subject,
          grade: scope.grade,
          name: kp.name as String,
        );
    if (!context.mounted) return;
    await AppDialog.alert(
      context,
      title: Text('「${kp.name}」的来源'),
      content: SizedBox(
        height: 440,
        child: SingleChildScrollView(
          child: KnowledgePointSourceView(
            kpName: kp.name as String,
            sources: sources.sources,
          ),
        ),
      ),
    );
  }
}

/// 范围选择条：**只列出真的传过教材的**学科 / 年级 / 学期（ADR-0065）。
///
/// 单独成 widget 是为了守 ADR-0058 的 400 行上限，但更实际的理由是级联逻辑在这里
/// 收口：切学科时年级要当场换成新学科的第一个可用年级（否则短暂出现一个不属于该
/// 学科的组合），切年级同理要把学期退回「整学年」。
class _ScopeBar extends ConsumerWidget {
  const _ScopeBar({required this.km});

  final KnowledgeManageState km;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void setScope(String subject, int grade, String semester) =>
        ref
            .read(knowledgeManageProvider.notifier)
            .setScope(subject, grade, semester);

    // ADR-0093：学期必须具体，切学科/年级时回落到该范围首个具体学期（不再有「整学年」）。
    String firstSemester(String subject, int grade) {
      final sems = km.semestersOf(subject, grade);
      return sems.isNotEmpty ? sems.first : '上学期';
    }

    return Row(
      children: [
        Expanded(
          child: AppPickerField<String>(
            label: '学科',
            values: km.subjects,
            labels: km.subjects,
            value: km.subject,
            onChanged: (v) => setScope(
              v,
              km.gradesOf(v).first,
              firstSemester(v, km.gradesOf(v).first),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: AppPickerField<int>(
            label: '年级',
            values: km.grades,
            labels: [for (final g in km.grades) '$g年级'],
            value: km.grade,
            // 换年级后旧学期可能不再存在（如只有上册）→ 落到该范围首个具体学期。
            onChanged: (v) => setScope(
              km.subject,
              v,
              firstSemester(km.subject, v),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: AppPickerField<String>(
            label: '学期',
            values: km.semesters,
            labels: km.semesters,
            value: km.semester,
            onChanged: (v) => setScope(km.subject, km.grade, v),
          ),
        ),
      ],
    );
  }
}

/// 审核覆盖度进度条（ADR-0093）：curated / total，扁平无阴影，配色走主题令牌。
class _CoverageMeter extends StatelessWidget {
  const _CoverageMeter({required this.total, required this.curated});

  final int total;
  final int curated;

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final ratio = total == 0 ? 0.0 : curated / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '审核覆盖度 ${((ratio * 100).round())}%（已确认 $curated / 共 $total）',
          style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 6,
            color: app.secondary.withValues(alpha: 0.18),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio,
              child: Container(color: app.primary),
            ),
          ),
        ),
      ],
    );
  }
}

  
