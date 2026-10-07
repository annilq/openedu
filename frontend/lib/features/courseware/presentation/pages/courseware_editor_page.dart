import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:flutter/material.dart' show MaterialPageRoute;

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
  });

  final String knowledgePointId;
  final String kpName;
  final String subject;
  final int grade;
  final String semester;

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
    Future.microtask(_loadOrCreate);
  }

  Future<void> _loadOrCreate() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      // 一个知识点可有多份课件，取最新一份继续编辑（ADR-0067 §3.2）。
      final list =
          await repo.listCourseware(knowledgePointId: widget.knowledgePointId);
      final CoursewareModel cw = list.isNotEmpty
          ? list.first
          : await repo.createCourseware(knowledgePointId: widget.knowledgePointId);
      if (!mounted) return;
      setState(() {
        _courseware = cw;
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

  /// 重新起草（T07）：取新草稿相对当前稿的逐段 diff，教师逐段选择「用新版 / 留旧版」
  /// 后，把合并结果经 [updateSections] 写回**同一课件**——不新建副本（不再先建后删）。
  Future<void> _redraft() async {
    if (_busy || _courseware == null) return;
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

  Future<void> _editSection(CoursewareSectionModel section) async {
    final updated = await showCoursewareSectionEditDialog(
      context,
      ref,
      section,
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
      MaterialPageRoute(
        builder: (_) => CoursewarePresentPage(coursewareId: cw.id),
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
    final cw = _courseware;
    if (cw == null) {
      return const Center(
        child: AppEmptyState(
          icon: LucideIcons.fileWarning,
          title: '课件为空',
          message: '未能加载课件，请重试。',
        ),
      );
    }
    final canTeach = !cw.isEmpty && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
