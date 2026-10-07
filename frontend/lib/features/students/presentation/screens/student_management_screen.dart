import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_avatar.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_chip.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_section_title.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../classes/domain/models/class_model.dart';
import '../providers/student_management_notifier.dart';
import '../../providers/student_management_provider.dart';

/// 学生管理页（ADR-0068 §2.3 / ticket 02 + 03）。
///
/// 学生按班级分组展示（含「未分班」分组），每组显示人数；支持按班级筛选、
/// 按姓名 / 学号搜索。每行直接显示该学生活跃错题数（醒目），并给行内入口直达
/// 其详情页错题页签——补偿导航重构后「切学生即看错题」被拉长的问题。
///
/// ticket 03：进入「选择」模式后可勾选多名学生，统一「移入班级」或「移出班级」，
/// 由后端 `POST /students/batch-reassign` 单事务完成（越权即整体回滚）。
///
/// 班级筛选纯客户端（全部 / 某班 / 未分班），只关键词走后端搜索；数据一次加载后
/// 客户端二次分组，大班（≥60）也不重复请求。
class StudentManagementScreen extends ConsumerStatefulWidget {
  final void Function(String studentId) onOpenStudent;

  const StudentManagementScreen({super.key, required this.onOpenStudent});

  @override
  ConsumerState<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

/// 「未分班」筛选哨兵值（与真实 classId 不会冲突）。
const String _kUnclassed = '__unclassed__';

/// 行描述：分组头或学生行（flat list 渲染，大班也不卡）。
sealed class _RowItem {
  const _RowItem();
}

class _HeaderRow extends _RowItem {
  final String title;
  final int count;
  const _HeaderRow(this.title, this.count);
}

class _StudentRow extends _RowItem {
  final UserModel student;
  const _StudentRow(this.student);
}

class _StudentManagementScreenState
    extends ConsumerState<StudentManagementScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  /// 班级筛选：null=全部、_kUnclassed=未分班、否则真实 classId。
  String? _filter;

  /// 选择模式（ticket 03）：开启后可勾选多名学生做批量操作。
  bool _selecting = false;
  final Set<String> _selected = {};

  /// 班级选择浮层（移入班级时弹出）。
  bool _pickingClass = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(studentManagementProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        ref.read(studentManagementProvider.notifier).load(keyword: v);
      }
    });
  }

  void _onFilterChanged(String? value) => setState(() => _filter = value);

  /// 当前筛选下可见的学生（用于「全选」与批量操作范围判断）。
  List<UserModel> _filteredStudents(List<UserModel> students) {
    return students.where((s) {
      if (_filter == null) return true;
      if (_filter == _kUnclassed) return s.classId == null;
      return s.classId == _filter;
    }).toList();
  }

  void _toggleSelecting() => setState(() {
        _selecting = !_selecting;
        _selected.clear();
      });

  void _toggleSelect(String id) => setState(() {
        if (_selected.contains(id)) {
          _selected.remove(id);
        } else {
          _selected.add(id);
        }
      });

  void _selectAll(List<UserModel> students) => setState(() {
        final ids = _filteredStudents(students).map((s) => s.id);
        if (_selected.containsAll(ids)) {
          _selected.clear();
        } else {
          _selected.addAll(ids);
        }
      });

  Future<void> _moveToClass(ClassModel cls) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    setState(() => _pickingClass = false);
    try {
      await ref.read(studentManagementProvider.notifier).batchReassign(
            classId: cls.id,
            studentIds: ids,
          );
      if (mounted) {
        AppToast.show(context, '已移动 ${ids.length} 名学生到「${cls.name}」');
        setState(() {
          _selecting = false;
          _selected.clear();
        });
      }
    } catch (e) {
      if (mounted) AppToast.error(context, e);
    }
  }

  Future<void> _moveOut() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    try {
      await ref.read(studentManagementProvider.notifier).batchReassign(
            classId: null,
            studentIds: ids,
          );
      if (mounted) {
        AppToast.show(context, '已移出 ${ids.length} 名学生');
        setState(() {
          _selecting = false;
          _selected.clear();
        });
      }
    } catch (e) {
      if (mounted) AppToast.error(context, e);
    }
  }

  List<_RowItem> _buildRows(
    List<UserModel> students,
    List<ClassModel> classes,
  ) {
    final filtered = _filteredStudents(students);

    final buckets = <String?, List<UserModel>>{};
    for (final s in filtered) {
      (buckets[s.classId] ??= []).add(s);
    }

    final rows = <_RowItem>[];
    for (final c in classes) {
      final list = buckets.remove(c.id);
      if (list != null && list.isNotEmpty) {
        rows.add(_HeaderRow(c.name, list.length));
        for (final s in list) {
          rows.add(_StudentRow(s));
        }
      }
    }
    final unclassed = buckets.remove(null);
    if (unclassed != null && unclassed.isNotEmpty) {
      rows.add(_HeaderRow('未分班', unclassed.length));
      for (final s in unclassed) {
        rows.add(_StudentRow(s));
      }
    }
    for (final entry in buckets.entries) {
      rows.add(_HeaderRow('其他班级', entry.value.length));
      for (final s in entry.value) {
        rows.add(_StudentRow(s));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studentManagementProvider);
    final students = state is StudentManagementLoaded
        ? state.students
        : const <UserModel>[];

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PageHeader(
              state: state,
              selecting: _selecting,
              selectedCount: _selected.length,
              visibleCount: _filteredStudents(students).length,
              onToggleSelecting: _toggleSelecting,
              onSelectAll: () => _selectAll(students),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    label: '搜索',
                    hintText: '按姓名或学号搜索',
                    controller: _search,
                    prefixIcon: LucideIcons.search,
                    onChanged: _onSearchChanged,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (state is StudentManagementLoaded)
                    _FilterChips(
                      classes: state.classes,
                      filter: _filter,
                      onChanged: _onFilterChanged,
                    ),
                ],
              ),
            ),
            Expanded(
              child: _Body(
                state: state,
                filter: _filter,
                selecting: _selecting,
                selected: _selected,
                onToggleSelect: _toggleSelect,
                onRetry: () =>
                    ref.read(studentManagementProvider.notifier).load(),
                onOpenStudent: widget.onOpenStudent,
                buildRows: _buildRows,
              ),
            ),
            if (_selecting)
              _ActionBar(
                selectedCount: _selected.length,
                onMoveOut: _moveOut,
                onPickClass: () => setState(() => _pickingClass = true),
                onCancel: _toggleSelecting,
              ),
          ],
        ),
        if (_pickingClass && state is StudentManagementLoaded)
          _ClassPicker(
            classes: state.classes,
            onPick: _moveToClass,
            onDismiss: () => setState(() => _pickingClass = false),
          ),
      ],
    );
  }
}

/// 页面标题行：标题 + 总数徽标；选择模式下切换为「选择/取消」与已选计数。
class _PageHeader extends StatelessWidget {
  final StudentManagementState state;
  final bool selecting;
  final int selectedCount;
  final int visibleCount;
  final VoidCallback onToggleSelecting;
  final VoidCallback onSelectAll;

  const _PageHeader({
    required this.state,
    required this.selecting,
    required this.selectedCount,
    required this.visibleCount,
    required this.onToggleSelecting,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final total = state is StudentManagementLoaded
        ? (state as StudentManagementLoaded).students.length
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          Text('学生管理', style: text.titleLarge),
          const SizedBox(width: AppSpacing.sm),
          if (!selecting && total != null)
            AppBadge(
              label: '$total 人',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
            ),
          const Spacer(),
          if (selecting) ...[
            AppBadge(
              label: '已选 $selectedCount',
              background: scheme.accent,
              foreground: scheme.onAccent,
            ),
            const SizedBox(width: AppSpacing.xs),
            AppTextAction(label: '全选', onPressed: onSelectAll),
          ],
          AppTextAction(
            label: selecting ? '取消' : '选择',
            onPressed: onToggleSelecting,
          ),
        ],
      ),
    );
  }
}

/// 班级筛选横滑 chip 行（全部 / 各班 / 未分班）。
class _FilterChips extends StatelessWidget {
  final List<ClassModel> classes;
  final String? filter;
  final void Function(String?) onChanged;

  const _FilterChips({
    required this.classes,
    required this.filter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = <_ChipOption>[
      const _ChipOption(label: '全部', value: null),
      for (final c in classes) _ChipOption(label: c.name, value: c.id),
      const _ChipOption(label: '未分班', value: _kUnclassed),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: AppChip(
                label: o.label,
                selected: filter == o.value,
                onTap: () => onChanged(o.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChipOption {
  final String label;
  final String? value;
  const _ChipOption({required this.label, required this.value});
}

/// 批量操作底部条：移出班级 / 移入班级（弹选择器） / 取消。
class _ActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onMoveOut;
  final VoidCallback onPickClass;
  final VoidCallback onCancel;

  const _ActionBar({
    required this.selectedCount,
    required this.onMoveOut,
    required this.onPickClass,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final enabled = selectedCount > 0;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceRaised,
        border: Border(
          top: BorderSide(color: scheme.outline, width: AppElevation.borderWidth),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          AppTextAction(
            label: '移出班级',
            onPressed: enabled ? onMoveOut : null,
          ),
          const SizedBox(width: AppSpacing.sm),
          AppTextAction(
            label: '移入班级',
            onPressed: enabled ? onPickClass : null,
            color: scheme.primary,
          ),
          const Spacer(),
          AppTextAction(label: '取消', onPressed: onCancel),
        ],
      ),
    );
  }
}

/// 移入班级的班级选择器（页内联浮层，不依赖 Material Dialog，保持无 Material 祖先）。
class _ClassPicker extends StatelessWidget {
  final List<ClassModel> classes;
  final void Function(ClassModel) onPick;
  final VoidCallback onDismiss;

  const _ClassPicker({
    required this.classes,
    required this.onPick,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            child: Container(color: scheme.scrim),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: scheme.outline,
                width: AppElevation.borderWidth,
              ),
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text('移入到班级', style: text.titleMedium),
                ),
                Container(height: 1, color: scheme.outline),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    children: [
                      for (final c in classes)
                        AppCard.listRow(
                          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          onTap: () => onPick(c),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(c.name,
                                    style: text.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    )),
                              ),
                              Text('${c.studentCount} 人',
                                  style: text.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  )),
                              const SizedBox(width: AppSpacing.xs),
                              Icon(LucideIcons.chevronRight,
                                  size: 16, color: scheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      if (classes.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Text('还没有班级，请先在侧栏新建班级。',
                              style: text.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              )),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 列表主体：按状态分流加载 / 错误 / 空 / 分组列表。
class _Body extends StatelessWidget {
  final StudentManagementState state;
  final String? filter;
  final bool selecting;
  final Set<String> selected;
  final void Function(String) onToggleSelect;
  final VoidCallback onRetry;
  final void Function(String studentId) onOpenStudent;
  final List<_RowItem> Function(List<UserModel>, List<ClassModel>) buildRows;

  const _Body({
    required this.state,
    required this.filter,
    required this.selecting,
    required this.selected,
    required this.onToggleSelect,
    required this.onRetry,
    required this.onOpenStudent,
    required this.buildRows,
  });

  @override
  Widget build(BuildContext context) {
    if (state is StudentManagementLoading ||
        state is StudentManagementInitial) {
      return const Center(child: AppLoading());
    }
    if (state is StudentManagementError) {
      return Center(
        child: AppError(
          message: (state as StudentManagementError).message,
          onRetry: onRetry,
        ),
      );
    }
    final loaded = state as StudentManagementLoaded;
    if (loaded.students.isEmpty) {
      return Center(
        child: AppEmptyState(
          icon: LucideIcons.users,
          title: '还没有学生',
          message: '从侧栏「添加学生」或批量导入花名册，学生会出现在这里。',
        ),
      );
    }

    final rows = buildRows(loaded.students, loaded.classes);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is _HeaderRow) {
          return SectionTitle(row.title,
              trailing: AppBadge(label: '${row.count} 人'));
        }
        final student = (row as _StudentRow).student;
        return _StudentTile(
          student: student,
          wrongCount: loaded.wrongCounts[student.id] ?? 0,
          selecting: selecting,
          selected: selected.contains(student.id),
          onTap: selecting
              ? () => onToggleSelect(student.id)
              : () => onOpenStudent(student.id),
        );
      },
    );
  }
}

/// 单个学生行：头像 + 姓名/学号 + 活跃错题数（醒目）+ 进入箭头。
/// 选择模式下行首显示勾选框，整行点击切换选中。
class _StudentTile extends StatelessWidget {
  final UserModel student;
  final int wrongCount;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;

  const _StudentTile({
    required this.student,
    required this.wrongCount,
    this.selecting = false,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final hasWrong = wrongCount > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard.listRow(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        onTap: onTap,
        child: Row(
          children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Icon(
                  selected ? LucideIcons.checkCircle : LucideIcons.circle,
                  size: 20,
                  color: selected ? scheme.accent : scheme.onSurfaceVariant,
                ),
              )
            else
              AvatarSquircle.xs(name: student.displayName),
            if (!selecting) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.displayName,
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (student.username.isNotEmpty)
                    Text(
                      '学号 ${student.username}',
                      style: text.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (!selecting)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: hasWrong ? scheme.accent : scheme.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(
                    color: scheme.outline,
                    width: AppElevation.borderWidthSm,
                  ),
                ),
                child: Text(
                  hasWrong ? '$wrongCount 道错题' : '无错题',
                  style: text.labelSmall?.copyWith(
                    color: hasWrong
                        ? scheme.onAccent
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (!selecting) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(LucideIcons.chevronRight,
                  size: 16, color: scheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }
}
