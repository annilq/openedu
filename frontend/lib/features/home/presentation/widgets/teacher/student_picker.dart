import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/domain/models/user.dart';
import '../../../../students/presentation/providers/students_notifier.dart';
import '../../../../students/providers/students_provider.dart';

/// 弹窗选择学生：列出本教师全部学生，点选即返回对应 [UserModel]。
///
/// 与已删除的 `selectedStudentProvider` 不同，这里**不写入任何全局状态**——
/// 只把选择结果交还给调用方（题库生成动作 / 布置任务表单内联选择器），
/// 由调用方显式使用。这样「题库」「布置任务」不再隐式依赖全局当前学生。
Future<UserModel?> pickStudent(BuildContext context, WidgetRef ref) async {
  return showShadDialog<UserModel?>(
    context: context,
    builder: (ctx) => ShadDialog.alert(
      title: const Text('选择学生'),
      child: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Consumer(
          builder: (c, r, _) {
            final state = r.watch(studentsNotifierProvider);
            final app = AppTheme.colorsOf(c);
            final text = AppTheme.textOf(c);
            if (state is ChildrenInitial || state is ChildrenLoading) {
              return const AppLoading();
            }
            if (state is ChildrenError) {
              return AppError(
                message: state.message,
                onRetry: () =>
                    r.read(studentsNotifierProvider.notifier).loadChildren(),
              );
            }
            if (state is! StudentsLoaded) return const SizedBox.shrink();
            if (state.students.isEmpty) {
              return AppEmptyState(
                icon: LucideIcons.users,
                title: '还没有学生',
                message: '先在「学生」中添加学生，再回来选择。',
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: state.students.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.xs),
              itemBuilder: (_, i) {
                final s = state.students[i];
                return AppFocusableAction(
                  onTap: () => Navigator.of(ctx).pop(s),
                  hoverHighlight: true,
                  semanticLabel: '选择 ${s.displayName}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: app.outline)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(s.displayName, style: text.bodyMedium),
                        ),
                        if (s.grade != null && s.grade! > 0)
                          Padding(
                            padding:
                                const EdgeInsets.only(right: AppSpacing.sm),
                            child: Text(
                              '${s.grade}年级',
                              style: text.labelSmall
                                  ?.copyWith(color: app.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ),
  );
}
