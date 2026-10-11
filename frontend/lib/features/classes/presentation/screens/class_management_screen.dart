import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../providers/class_management_notifier.dart';
import '../providers/class_management_provider.dart';

part 'class_management_form.dart';

/// 班级管理页（ADR-0086 容器）。
///
/// 班级卡片列表（名称 + 年级 + 人数 + 下钻箭头）；顶部「+ 新建班级」内联表单；
/// 行内「重命名 / 删除」走页内浮层（不依赖 Material `Dialog`，保持无 Material 祖先）。
/// 点卡片下钻到该班学生管理页（[onOpenClass]，由 ticket 04 消费）。
class ClassManagementScreen extends ConsumerStatefulWidget {
  final void Function(String classId, String className) onOpenClass;

  const ClassManagementScreen({super.key, required this.onOpenClass});

  @override
  ConsumerState<ClassManagementScreen> createState() =>
      _ClassManagementScreenState();
}

class _ClassManagementScreenState extends ConsumerState<ClassManagementScreen> {
  bool _creating = false;

  /// 正在重命名的班级（底部抽屉表单），null = 不显示。
  ClassModel? _editing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(classManagementProvider.notifier).load();
    });
  }

  Future<void> _confirmDelete(ClassModel cls) async {
    final ok = await AppDialog.confirm(
      context,
      title: const Text('删除班级'),
      content: Text(
        '删除「${cls.name}」后，班内 ${cls.studentCount} 名学生会转为未分班，'
        '账号与错题保留。此操作不可撤销。',
      ),
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(classManagementProvider.notifier).deleteClass(cls.id);
      if (mounted) {
        AppToast.show(context, '${cls.studentCount} 名学生已转为未分班');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(classManagementProvider);
    final classes = state is ClassManagementLoaded
        ? state.classes
        : const <ClassModel>[];

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              creating: _creating,
              total: classes.length,
              onToggleCreate: () => setState(() => _creating = !_creating),
            ),
            if (_creating)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                child: _ClassForm(
                  initialName: '',
                  initialGrade: 1,
                  onSubmit: (name, grade) async {
                    try {
                      await ref
                          .read(classManagementProvider.notifier)
                          .createClass(name: name, grade: grade);
                      if (mounted) setState(() => _creating = false);
                    } catch (e) {
                      // ignore: use_build_context_synchronously
                      if (mounted) AppToast.error(context, e);
                    }
                  },
                  onCancel: () => setState(() => _creating = false),
                ),
              ),
            Expanded(
              child: _Body(
                state: state,
                onOpenClass: widget.onOpenClass,
                onRename: (cls) => setState(() => _editing = cls),
                onDelete: _confirmDelete,
                onCreate: () => setState(() => _creating = true),
              ),
            ),
          ],
        ),
        if (_editing != null)
          _ClassFormSheet(
            classModel: _editing!,
            onClose: () => setState(() => _editing = null),
            onSubmit: (name, grade) async {
              final cls = _editing!;
              try {
                await ref
                    .read(classManagementProvider.notifier)
                    .updateClass(id: cls.id, name: name, grade: grade);
                if (mounted) setState(() => _editing = null);
              } catch (e) {
                // ignore: use_build_context_synchronously
                if (mounted) AppToast.error(context, e);
              }
            },
          ),
      ],
    );
  }
}

/// 页头：标题 + 总数徽标 +「+ 新建班级」入口（新建中隐藏，避免与内联表单重复）。
class _Header extends StatelessWidget {
  final bool creating;
  final int total;
  final VoidCallback onToggleCreate;

  const _Header({
    required this.creating,
    required this.total,
    required this.onToggleCreate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          Text('班级管理', style: text.titleLarge),
          const SizedBox(width: AppSpacing.sm),
          if (!creating)
            AppBadge(
              label: '$total 个',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
            ),
          const Spacer(),
          if (!creating)
            AppIconAction(
              icon: LucideIcons.plus,
              semanticLabel: '新建班级',
              onPressed: onToggleCreate,
            ),
        ],
      ),
    );
  }
}

/// 列表主体：按状态分流加载 / 错误 / 空 / 卡片列表。
class _Body extends StatelessWidget {
  final ClassManagementState state;
  final void Function(String classId, String className) onOpenClass;
  final void Function(ClassModel) onRename;
  final Future<void> Function(ClassModel) onDelete;
  final VoidCallback onCreate;

  const _Body({
    required this.state,
    required this.onOpenClass,
    required this.onRename,
    required this.onDelete,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    if (state is ClassManagementInitial ||
        state is ClassManagementLoading) {
      return const Center(child: AppLoading());
    }
    if (state is ClassManagementError) {
      return Center(
        child: AppError(
          message: (state as ClassManagementError).message,
          onRetry: () {},
        ),
      );
    }
    final classes = (state as ClassManagementLoaded).classes;
    if (classes.isEmpty) {
      return AppEmptyState(
        icon: LucideIcons.school,
        title: '还没有班级',
        message: '班级承载年级与分班。点「新建班级」开始把学生分组。',
        actionLabel: '新建班级',
        actionIcon: LucideIcons.plus,
        onAction: onCreate,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: classes.length,
      itemBuilder: (context, i) => _ClassCard(
        cls: classes[i],
        onOpenClass: onOpenClass,
        onRename: onRename,
        onDelete: onDelete,
      ),
    );
  }
}

/// 单张班级卡片：名称 + 年级 + 人数 + 下钻箭头；行内重命名 / 删除。
///
/// 卡片本身不承接 onTap（避免与内部行内操作的命中区嵌套导致双重触发）；下钻由
/// 主区 [AppFocusableAction] 承接，重命名 / 删除是并行的 [AppIconAction] 兄弟节点。
class _ClassCard extends StatelessWidget {
  final ClassModel cls;
  final void Function(String classId, String className) onOpenClass;
  final void Function(ClassModel) onRename;
  final Future<void> Function(ClassModel) onDelete;

  const _ClassCard({
    required this.cls,
    required this.onOpenClass,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard.listRow(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: AppFocusableAction(
                onTap: () => onOpenClass(cls.id, cls.name),
                semanticLabel: '打开 ${cls.name}',
                hoverHighlight: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cls.name,
                            style: text.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs2),
                          Text(
                            '${cls.grade} 年级 · ${cls.studentCount} 人',
                            style: text.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(LucideIcons.chevronRight,
                        size: 16, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            AppIconAction(
              icon: LucideIcons.pencil,
              semanticLabel: '重命名 ${cls.name}',
              onPressed: () => onRename(cls),
            ),
            AppIconAction(
              icon: LucideIcons.trash2,
              color: scheme.error,
              semanticLabel: '删除 ${cls.name}',
              onPressed: () => onDelete(cls),
            ),
          ],
        ),
      ),
    );
  }
}

