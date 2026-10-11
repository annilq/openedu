import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_pushed_page.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../domain/models/courseware.dart';
import '../../domain/models/courseware_section.dart';
import '../../providers/courseware_provider.dart';
import '../widgets/courseware_editor_info_card.dart';
import '../widgets/editor_section_list.dart';
import 'courseware_present_page.dart';
import 'courseware_section_edit_dialog.dart';
import 'courseware_info_edit_dialog.dart';

/// 课件编辑器（ADR-0067 §6 切片 4 / §3.8）：备课主视图。
///
/// 从知识点行的「课件」入口进来。自身负责「这个知识点有没有课件」：有就打开最新的那份，
/// 没有就停在空态，由用户主动新建一份**空课件**（ADR-0085：不再 AI 起草）。所有讲解安排
/// 都落在课件上，**不与知识点的 `scenes` 混**——课件是 `scenes` 的上位容器（§3.1）。
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
      // 只查「这个知识点有没有课件」。**不自动建**——没有就停在空态，由用户点
      // 「新增课件」主动建一份空课件。
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

  /// 首次生成（courseware-round-3 T01）：用户点「新增课件」才建一份**空课件**
  /// （零环节，不调模型，ADR-0085）。随后教师手动添加环节。期间 [_busy] 为真，
  /// 页面给「正在创建课件」提示。
  Future<void> _createFirst() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      final created = await repo.createCourseware(
        knowledgePointId: widget.knowledgePointId,
      );
      if (!mounted) return;
      setState(() => _courseware = created);
      AppToast.show(context, '已创建空课件，可添加环节');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '创建课件失败：$e');
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
      kpName: widget.kpName,
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

  /// 手动添加环节（T04 入口补强）：空课件态也能发起——这是唯一的编排入口。
  ///
  /// 与 [CoursewareEditorSectionList._addSection] 同一份逻辑：打开与编辑同构的空白
  /// 表单，保存后把新环节追加到列表末尾，经 [updateSections] 整体覆盖写落库。空态 CTA
  /// 与列表头「添加环节」复用此处，单一事实源。
  Future<void> _addSection() async {
    final cw = _courseware;
    if (cw == null || _busy) return;
    final created = await showCoursewareSectionEditDialog(
      context,
      ref,
      CoursewareSectionModel(),
      knowledgePointId: widget.knowledgePointId,
      kpName: widget.kpName,
      subject: widget.subject,
      grade: widget.grade,
      semester: widget.semester,
    );
    if (created == null || _courseware == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      final next = [..._courseware!.sections, created];
      final saved = await repo.updateSections(_courseware!.id, next);
      if (!mounted) return;
      setState(() => _courseware = saved);
      AppToast.show(context, '已添加环节');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '添加环节失败：$e');
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
  /// 备课行的主操作位。
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

  Widget _buildBody(AppText text) {
    if (_loading) {
      return const Center(child: AppLoading());
    }
    if (_error != null) {
      return Center(child: AppError(message: _error!, onRetry: _loadOrCreate));
    }
    // 显式创建中（点「新增课件」后）：明确告知正在建空壳，替代原无文案空白页。
    if (_busy && _courseware == null) {
      return const Center(
        child: AppLoading(message: '正在创建课件…'),
      );
    }
    final cw = _courseware;
    if (cw == null) {
      // 还没有课件：停在空态，由用户主动发起（点「新增课件」建一份空课件）。
      return Center(
        child: AppEmptyState(
          icon: LucideIcons.sparkles,
          title: '还没有课件',
          message: '点「新增课件」按这个知识点建一份空课件，随后手动添加讲解环节。',
          actionLabel: '新增课件',
          onAction: _createFirst,
        ),
      );
    }
    final canTeach = !cw.isEmpty && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoursewareEditorInfoCard(
          courseware: cw,
          onEdit: _busy ? null : _editInfo,
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(child: Text('备课', style: text.bodyMedium)),
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
              message: '点「添加环节」手动设计这个知识点的讲解环节。',
              actionLabel: '添加环节',
              onAction: _addSection,
            ),
          )
        else
          Expanded(
            child: CoursewareEditorSectionList(
              sections: cw.sections,
              onReorder: _persistReorder,
              onDeleteSelected: _persistDelete,
              onEdit: _editSection,
              knowledgePointId: widget.knowledgePointId,
              kpName: widget.kpName,
              subject: widget.subject,
              grade: widget.grade,
              semester: widget.semester,
            ),
          ),
      ],
    );
  }
}
