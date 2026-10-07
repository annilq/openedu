import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/presentation/resource.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_scroll_page.dart';
import '../../../../shared/widgets/app_section_title.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../review/presentation/providers/review_notifier.dart';
import '../../../students/presentation/providers/students_notifier.dart';
import '../../../students/providers/students_provider.dart';
import '../../../tutor/presentation/providers/tutor_logs_notifier.dart';
import '../providers/home_notifier.dart';
import '../teacher_pages.dart';
import '../widgets/teacher/teacher_tutor_logs_view.dart';
import '../widgets/teacher/teacher_wrong_questions_view.dart';

/// 学生详情页：接收 `studentId` 参数，以**局部**页签切换概览 / 错题本 / AI 答疑。
///
/// 三页签数据都按本学生加载（不再依赖全局 `selectedStudentProvider`），页签状态也是
/// 本页私有的——与 14 协同前，侧栏旧入口与这里并存、互不干扰；14 上线后旧入口移除。
class StudentDetailScreen extends ConsumerStatefulWidget {
  final String studentId;
  final StudentDetailTab initialTab;
  final VoidCallback? onBack;

  const StudentDetailScreen({
    super.key,
    required this.studentId,
    this.initialTab = StudentDetailTab.overview,
    this.onBack,
  });

  @override
  ConsumerState<StudentDetailScreen> createState() =>
      _StudentDetailScreenState();
}

class _StudentDetailScreenState extends ConsumerState<StudentDetailScreen> {
  late StudentDetailTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    // 按本学生加载三页签数据；推到下一帧避免 build 期间改被 watch 的 provider。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(teacherWrongQuestionsProvider.notifier).load(widget.studentId);
      ref
          .read(teacherGraduatedWrongQuestionsProvider.notifier)
          .load(widget.studentId);
      ref.read(tutorLogsNotifierProvider.notifier).load(widget.studentId);
      ref.read(progressNotifierProvider.notifier).load(widget.studentId);
      ref.read(masteryNotifierProvider.notifier).load(widget.studentId);
    });
  }

  void _selectTab(StudentDetailTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
  }

  UserModel? _studentOf() {
    final state = ref.watch(studentsNotifierProvider);
    if (state is StudentsLoaded) {
      for (final c in state.students) {
        if (c.id == widget.studentId) return c;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final student = _studentOf();
    final name = student?.displayName ?? '学生';
    final grade = student?.grade;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(name: name, grade: grade, onBack: widget.onBack),
        _TabBar(tab: _tab, onSelect: _selectTab),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case StudentDetailTab.overview:
        return _StudentOverview(
          studentId: widget.studentId,
          onOpenWrongQuestions: () => _selectTab(StudentDetailTab.wrongQuestions),
          onOpenTutorLogs: () => _selectTab(StudentDetailTab.tutorLogs),
        );
      case StudentDetailTab.wrongQuestions:
        return TeacherWrongQuestionsView(studentId: widget.studentId);
      case StudentDetailTab.tutorLogs:
        return TeacherTutorLogsView(studentId: widget.studentId);
    }
  }
}

/// 页头：返回 + 学生名 + 年级。
class _Header extends StatelessWidget {
  final String name;
  final int? grade;
  final VoidCallback? onBack;
  const _Header({required this.name, this.grade, this.onBack});

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onBack != null)
            AppIconAction(
              icon: LucideIcons.arrowLeft,
              semanticLabel: '返回',
              onPressed: onBack,
            ),
          Expanded(
            child: Text(
              name,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (grade != null && grade! > 0)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text('$grade年级',
                  style: text.labelMedium
                      ?.copyWith(color: AppTheme.colorsOf(context).onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

/// 页签切换器：三档自定义分段控件（Material-free，与侧栏选中语言一致）。
class _TabBar extends StatelessWidget {
  final StudentDetailTab tab;
  final void Function(StudentDetailTab) onSelect;
  const _TabBar({required this.tab, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final items = const [
      (StudentDetailTab.overview, '概览'),
      (StudentDetailTab.wrongQuestions, '错题本'),
      (StudentDetailTab.tutorLogs, 'AI 答疑'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 0),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final (t, label) in items)
            _TabChip(
              label: label,
              active: tab == t,
              onTap: () => onSelect(t),
              scheme: scheme,
            ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final AppColors scheme;
  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return AppFocusableAction(
      onTap: onTap,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      hoverHighlight: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: active ? scheme.surfaceActive : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: scheme.outline,
            width: AppElevation.borderWidthHairline,
          ),
        ),
        child: Text(
          label,
          style: text.labelMedium?.copyWith(
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 概览页签：进度快照 + 两个直达页签的快捷入口。
class _StudentOverview extends ConsumerWidget {
  final String studentId;
  final VoidCallback onOpenWrongQuestions;
  final VoidCallback onOpenTutorLogs;
  const _StudentOverview({
    required this.studentId,
    required this.onOpenWrongQuestions,
    required this.onOpenTutorLogs,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progState = ref.watch(progressNotifierProvider);
    final progress = progState.dataOrNull;
    return AppScrollPage(
      children: [
        const SectionTitle('学习进度'),
        _buildProgress(context, progState, progress),
        const SectionTitle('快捷查看'),
        _QuickLink(
          icon: LucideIcons.bookOpen,
          label: '查看错题本',
          onTap: onOpenWrongQuestions,
        ),
        const SizedBox(height: AppSpacing.sm),
        _QuickLink(
          icon: LucideIcons.sparkles,
          label: '查看 AI 答疑记录',
          onTap: onOpenTutorLogs,
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context, Resource<ProgressModel> state,
      ProgressModel? progress) {
    if (state is ResourceError) {
      return AppError(message: state.errorOrNull ?? '');
    }
    if (progress == null) {
      return const AppLoading.skeletonInline(skeletonLines: 2);
    }
    final text = AppTheme.textOf(context);
    final scheme = AppTheme.colorsOf(context);
    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(label,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Text(
                value,
                style: text.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(LucideIcons.flame, '连续打卡', '${progress.streakDays} 天'),
          row(LucideIcons.listOrdered, '总题数', '${progress.total}'),
          row(LucideIcons.checkCircle2, '答对', '${progress.correct}'),
          row(LucideIcons.barChart3, '正确率',
              '${(progress.accuracy * 100).round()}%'),
        ],
      ),
    );
  }
}

/// 概览里的「直达页签」快捷入口。
class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    return AppCard.listRow(
      onTap: onTap,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label, style: AppTheme.textOf(context).bodyMedium),
          ),
          Icon(LucideIcons.chevronRight,
              size: 16, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
