import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_pushed_page.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../domain/models/courseware.dart';
import '../../domain/models/courseware_section.dart';
import '../../providers/courseware_provider.dart';
import '../widgets/editor_section_list.dart';
import '../widgets/courseware_redraft_dialog.dart';
import 'courseware_present_page.dart';
import 'courseware_section_edit_dialog.dart';
import 'courseware_info_edit_dialog.dart';

/// 课件编辑器（ADR-0067 §6 切片 4 / §3.8）：备课主视图。
///
/// 从知识点行的「课件」入口进来。自身负责「这个知识点有没有课件」：有就打开最新的那份，
/// 没有就走 AI 起草（决策 2）。所有讲解安排都落在课件上，**不与知识点的 `scenes` 混**——
/// 课件是 `scenes` 的上位容器（§3.1）。
///
/// 演示态由本页 push 出去（[CoursewarePresentPage] 自带全屏框）。
class CoursewareEditorPage extends ConsumerStatefulWidget {
  const CoursewareEditorPage({
    super.key,
    required this.knowledgePointId,
    required this.kpName,
    required this.subject,
    required this.grade,
    required this.semester,
    this.initialCourseware,
  });

  final String knowledgePointId;
  final String kpName;
  final String subject;
  final int grade;
  final String semester;

  /// 预载课件（courseware-round-3 T01）：由「新增课件」表单建好空壳后直接带上，
  /// 跳过 `_loadOrCreate` 的按 KP 查询——既省一次往返，也避免同 KP 多课件时取到旧份。
  final CoursewareModel? initialCourseware;

  @override
  ConsumerState<CoursewareEditorPage> createState() =>
      _CoursewareEditorPageState();
}

class _CoursewareEditorPageState extends ConsumerState<CoursewareEditorPage> {
  CoursewareModel? _courseware;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 预载课件：直接进入已建好的空壳，无需再按 KP 查一遭。
    if (widget.initialCourseware != null) {
      _courseware = widget.initialCourseware;
      _loading = false;
      return;
    }
    Future.microtask(_loadOrCreate);
  }

  Future<void> _loadOrCreate() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      // 只查「这个知识点有没有课件」。**不自动建、不自动让 AI 起草**——没有就停在
      // 空态，由用户点「新增课件信息」主动触发（决策 2 改为显式发起，避免进入即空白等待）。
      final list =
          await repo.listCourseware(knowledgePointId: widget.knowledgePointId);
      if (!mounted) return;
      setState(() {
        _courseware = list.isNotEmpty ? list.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 首次生成（决策 2 的显式发起）：用户点「新增课件信息」才调用，由后端按知识点
  /// 跑 AI 起草并返回完整课件。期间保持 [_courseware] 为 null + [_busy] 为真，
  /// 页面显示「AI 正在生成课件」提示，不再是毫无反馈的空白页。
  Future<void> _createFirst() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      final created = await repo.createCourseware(
          knowledgePointId: widget.knowledgePointId);
      if (!mounted) return;
      setState(() => _courseware = created);
      AppToast.show(context, '已生成课件讲解安排');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '生成课件失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 重新起草（T07）：取新草稿相对当前稿的逐段 diff，教师逐段选择「用新版 / 留旧版」
  /// 后，把合并结果经 [updateSections] 写回**同一课件**——不新建副本（不再先建后删）。
  Future<void> _redraft() async {    if (_busy || _courseware == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      final diff = await repo.getRedraftDiff(_courseware!.id);
      if (!mounted) return;
      final merged = await showCoursewareRedraftDialog(context, diff);
      if (merged == null) return; // 用户取消，原课件不动
      final saved = await repo.updateSections(_courseware!.id, merged);
      if (!mounted) return;
      setState(() => _courseware = saved);
      AppToast.show(context, '已按所选写回本课件');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '重新起草失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 编辑课件信息（courseware-round-3 T02）：标题 / 状态。复用已有
  /// `PATCH /courses/{id}`（[updateCourseware]），无需新端点。
  Future<void> _editInfo() async {
    final cw = _courseware;
    if (cw == null || _busy) return;
    final updated = await showCoursewareInfoEditDialog(context, cw);
    if (updated == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(coursewareRepositoryProvider)
          .updateCourseware(cw.id, title: updated.title, status: updated.status);
      if (!mounted) return;
      setState(() => _courseware = saved);
      AppToast.show(context, '已更新课件信息');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '保存课件信息失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSection(CoursewareSectionModel section) async {
    final updated = await showCoursewareSectionEditDialog(
      context,
      ref,
      section,
      knowledgePointId: widget.knowledgePointId,
      subject: widget.subject,
      grade: widget.grade,
      semester: widget.semester,
    );
    if (updated == null || _courseware == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      final next = _courseware!.sections
          .map((s) => s.id == updated.id ? updated : s)
          .toList();
      final saved = await repo.updateSections(_courseware!.id, next);
      if (!mounted) return;
      setState(() => _courseware = saved);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '保存环节失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 重排：整体覆盖写环节序列（ADR-0067 §3.2，`updateSections` 整列覆盖）。
  Future<void> _persistReorder(List<CoursewareSectionModel> next) async {
    if (_courseware == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      final saved = await repo.updateSections(_courseware!.id, next);
      if (!mounted) return;
      setState(() => _courseware = saved);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '重排失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 批量删：从当前序列剔除被选中 id 后整体覆盖写。
  Future<void> _persistDelete(List<String> ids) async {
    if (_courseware == null) return;
    final next =
        _courseware!.sections.where((s) => !ids.contains(s.id)).toList();
    await _persistReorder(next);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return AppPushedPage(
      background: AppTheme.colorsOf(context).surface,
      title: widget.kpName,
      child: _buildBody(text),
    );
  }

  /// 进入演示态（push 全屏页，自带全屏框 + 退出入口，见 [CoursewarePresentPage]）。
  ///
  /// ⚠️ 不走 [AppPushedPage.trailing]：顶栏右侧只有 40 宽槽位、只允许单个图标行动，
  /// 「开始讲课」是带文字的主按钮，放进 40 宽槽会撑爆（实测 45px 右溢出）。它归到
  /// 备课行的主操作位，与「AI 重新起草」并列。
  void _openPresent() {
    final cw = _courseware;
    if (cw == null) return;
    Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => CoursewarePresentPage(coursewareId: cw.id),
      ),
    );
  }

  /// 课件信息卡片（courseware-round-3 T02）：标题 / 范围 / 状态 / 教学目标，
  /// 右上角「编辑」打开信息编辑弹窗（复用已有 `PATCH /{id}`）。
  Widget _infoCard(CoursewareModel cw, AppText text) {
    final app = AppTheme.colorsOf(context);
    final scope = [
      if (cw.subject != null && cw.subject!.isNotEmpty) cw.subject!,
      if (cw.grade != null) '${cw.grade}年级',
      if (cw.semester != null && cw.semester!.isNotEmpty) cw.semester!,
    ].join(' · ');
    final scopeLabel = scope.isEmpty ? cw.kpName : '$scope · ${cw.kpName}';
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surfaceRaised,
        border: Border.all(color: app.outline, width: AppElevation.borderWidth),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  cw.displayTitle,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              AppTextAction(label: '编辑', onPressed: _busy ? null : _editInfo),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(scopeLabel,
              style: text.bodySmall?.copyWith(color: app.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: cw.isReady ? app.primaryContainer : app.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  cw.isReady ? '可上讲台' : '草稿',
                  style: text.labelSmall?.copyWith(
                    color: cw.isReady ? app.onPrimaryContainer : app.onSurfaceVariant,
                  ),
                ),
              ),
              if (cw.objective != null && cw.objective!.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '目标：${cw.objective}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall
                        ?.copyWith(color: app.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppText text) {
    if (_loading) {
      return const Center(child: AppLoading());
    }
    if (_error != null) {
      return Center(child: AppError(message: _error!, onRetry: _loadOrCreate));
    }
    // 显式生成中（点「新增课件信息」后）：明确告知 AI 正在起草，替代原无文案空白页。
    if (_busy && _courseware == null) {
      return const Center(
        child: AppLoading(message: 'AI 正在生成课件，请稍候…'),
      );
    }
    final cw = _courseware;
    if (cw == null) {
      // 还没有课件：停在空态，由用户主动发起（点「新增课件信息」才调 AI 起草）。
      return Center(
        child: AppEmptyState(
          icon: LucideIcons.sparkles,
          title: '还没有课件',
          message: '点「新增课件信息」按这个知识点生成一份讲解安排。',
          actionLabel: '新增课件信息',
          onAction: _createFirst,
        ),
      );
    }
    final canTeach = !cw.isEmpty && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoCard(cw, text),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(child: Text('备课', style: text.bodyMedium)),
              AppTextAction(
                label: _busy ? '处理中…' : 'AI 重新起草',
                onPressed: _busy ? null : _redraft,
              ),
              const SizedBox(width: AppSpacing.sm),
              AppPrimaryButton(
                label: '开始讲课',
                fullWidth: false,
                onPressed: canTeach ? _openPresent : null,
              ),
            ],
          ),
        ),
        if (cw.isEmpty)
          Expanded(
            child: AppEmptyState(
              icon: LucideIcons.sparkles,
              title: '还没有讲解安排',
              message: '点「AI 重新起草」按这个知识点生成一份环节草案。',
            ),
          )
        else
          Expanded(
            child: CoursewareEditorSectionList(
              sections: cw.sections,
              onReorder: _persistReorder,
              onDeleteSelected: _persistDelete,
              onEdit: _editSection,
            ),
          ),
      ],
    );
  }
}
