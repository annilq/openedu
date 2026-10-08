import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../domain/models/courseware.dart';
import '../../providers/courseware_provider.dart';
import '../pages/courseware_editor_page.dart';
import '../pages/courseware_present_page.dart';
import 'package:kids_learn/features/home/presentation/widgets/teacher/courseware_recent_bar.dart';

/// 课件中心（方案A：侧栏「课件」一级入口，ADR-0070 之外的新增规划）。
///
/// 列出本教师全部课件（课件按知识点组织：一份知识点一串环节），点击直达
/// 编辑 / 讲课。顶部复用「最近课件」捷径（有则显示、无则收起）。空态引导去
/// 资料库按知识点备课——那里仍是课件真正的创建入口。
class CoursewareCenterScreen extends ConsumerWidget {
  const CoursewareCenterScreen({super.key});

  /// 全量查询：四个筛选项皆空 = 本教师全部课件（见 [coursewareListProvider]）。
  static const _allQuery = (
    knowledgePointId: null,
    subject: null,
    grade: null,
    semester: null,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(coursewareListProvider(_allQuery));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CoursewareRecentBar(),
        Expanded(
          child: list.when(
            loading: () => const Center(child: AppLoading(message: '加载课件列表…')),
            error: (e, _) => Center(
              child: AppError(
                message: '加载失败：$e',
                onRetry: () => ref.refresh(coursewareListProvider(_allQuery)),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: AppEmptyState(
                    icon: LucideIcons.bookOpen,
                    title: '还没有课件',
                    message: '课件按知识点组织：去「资料库」选一个知识点，点它的'
                        '「课件」按钮即可备课、讲课。',
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _CoursewareCard(cw: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CoursewareCard extends StatelessWidget {
  final CoursewareModel cw;
  const _CoursewareCard({required this.cw});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final canEdit = cw.knowledgePointId != null && cw.knowledgePointId!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: app.surfaceRaised,
        border: Border.all(color: app.outline, width: AppElevation.borderWidth),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cw.displayTitle,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    if (cw.subject != null && cw.subject!.isNotEmpty) cw.subject!,
                    if (cw.grade != null) '${cw.grade}年级',
                    if (cw.semester != null && cw.semester!.isNotEmpty)
                      cw.semester!,
                  ].join(' · '),
                  style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${cw.sections.length} 个环节 · ${cw.isReady ? "可上讲台" : "草稿"}'
                  '${cw.kpMissing ? " · 知识点已移除" : ""}',
                  style: text.bodySmall?.copyWith(color: app.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (canEdit)
            AppTextAction(
              label: '编辑',
              onPressed: () => _edit(context, cw),
            ),
          AppTextAction(
            label: '讲课',
            color: app.primary,
            onPressed: () => _present(context, cw),
          ),
        ],
      ),
    );
  }

  void _edit(BuildContext context, CoursewareModel cw) {
    Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => CoursewareEditorPage(
          knowledgePointId: cw.knowledgePointId!,
          kpName: cw.kpName,
          subject: cw.subject ?? '',
          grade: cw.grade ?? 0,
          semester: cw.semester ?? '',
        ),
      ),
    );
  }

  void _present(BuildContext context, CoursewareModel cw) {
    Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => CoursewarePresentPage(coursewareId: cw.id),
      ),
    );
  }
}
