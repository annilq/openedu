import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:flutter/material.dart' show MaterialPageRoute;

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_pushed_page.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../domain/models/courseware.dart';
import '../../domain/models/courseware_section.dart';
import '../../domain/models/courseware_section_kind.dart';
import '../../providers/courseware_provider.dart';
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

  /// 重新起草：先建新课件，成功后再删旧档（先建后删——建失败旧档仍在，不会丢）。
  Future<void> _redraft() async {
    if (_busy || _courseware == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(coursewareRepositoryProvider);
      final created =
          await repo.createCourseware(knowledgePointId: widget.knowledgePointId);
      if (_courseware != null && _courseware!.id.isNotEmpty) {
        await repo.deleteCourseware(_courseware!.id);
      }
      if (!mounted) return;
      setState(() => _courseware = created);
      AppToast.show(context, '已按该知识点重新起草讲解安排');
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

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final cw = _courseware;
    final canTeach = cw != null && !cw.isEmpty && !_busy;
    return AppPushedPage(
      title: widget.kpName,
      trailing: canTeach
          ? AppPrimaryButton(
              label: '开始讲课',
              fullWidth: false,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CoursewarePresentPage(coursewareId: cw.id),
                ),
              ),
            )
          : null,
      child: _buildBody(app, text),
    );
  }

  Widget _buildBody(AppColors app, AppText text) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${cw.sections.length} 个讲解环节',
                  style: text.bodyMedium,
                ),
              ),
              AppTextAction(
                label: _busy ? '起草中…' : 'AI 重新起草',
                onPressed: _busy ? null : _redraft,
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
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              itemCount: cw.sections.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) => _sectionCard(cw.sections[i], app, text),
            ),
          ),
      ],
    );
  }

  Widget _sectionCard(CoursewareSectionModel s, AppColors app, AppText text) {
    final kindLabel = s.isUnknownKind
        ? '未知环节'
        : kCoursewareSectionKindLabels[s.kind] ?? s.kind!.value;
    final icon = switch (s.kind) {
      CoursewareSectionKind.mediaGallery => LucideIcons.images,
      CoursewareSectionKind.interactiveScene => LucideIcons.shapes,
      CoursewareSectionKind.practice => LucideIcons.penLine,
      _ => LucideIcons.circleHelp,
    };
    return AppCard(
      onTap: () => _editSection(s),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: AppSpacing.xl, color: app.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title.isEmpty ? kindLabel : s.title,
                    style: text.titleMedium,
                  ),
                  if (s.script.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      s.script,
                      style: text.bodySmall?.copyWith(color: app.secondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              kindLabel,
              style: text.labelSmall?.copyWith(color: app.secondary),
            ),
          ],
        ),
      ),
    );
  }
}
