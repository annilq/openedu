import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_avatar.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_chip.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_section_title.dart';
import '../../../classes/domain/models/class_model.dart';
import '../providers/student_management_notifier.dart';
import '../../providers/student_management_provider.dart';

/// 学生管理页（ADR-0068 §2.3 / ticket 02）。
///
/// 学生按班级分组展示（含「未分班」分组），每组显示人数；支持按班级筛选、
/// 按姓名 / 学号搜索。每行直接显示该学生活跃错题数（醒目），并给行内入口直达
/// 其详情页错题页签——补偿导航重构后「切学生即看错题」被拉长的问题。
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

  List<_RowItem> _buildRows(
    List<UserModel> students,
    List<ClassModel> classes,
  ) {
    final filtered = students.where((s) {
      if (_filter == null) return true;
      if (_filter == _kUnclassed) return s.classId == null;
      return s.classId == _filter;
    }).toList();

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(state: state),
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
            onRetry: () =>
                ref.read(studentManagementProvider.notifier).load(),
            onOpenStudent: widget.onOpenStudent,
            buildRows: _buildRows,
          ),
        ),
      ],
    );
  }
}

/// 页面标题行：标题 + 总数徽标。
class _PageHeader extends StatelessWidget {
  final StudentManagementState state;
  const _PageHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final st = state;
    final total = st is StudentManagementLoaded ? st.students.length : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          Text('学生管理', style: text.titleLarge),
          const SizedBox(width: AppSpacing.sm),
          if (total != null)
            AppBadge(
              label: '$total 人',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
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

/// 列表主体：按状态分流加载 / 错误 / 空 / 分组列表。
class _Body extends StatelessWidget {
  final StudentManagementState state;
  final String? filter;
  final VoidCallback onRetry;
  final void Function(String studentId) onOpenStudent;
  final List<_RowItem> Function(List<UserModel>, List<ClassModel>) buildRows;

  const _Body({
    required this.state,
    required this.filter,
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
          onTap: () => onOpenStudent(student.id),
        );
      },
    );
  }
}

/// 单个学生行：头像 + 姓名/学号 + 活跃错题数（醒目）+ 进入箭头。
class _StudentTile extends StatelessWidget {
  final UserModel student;
  final int wrongCount;
  final VoidCallback onTap;

  const _StudentTile({
    required this.student,
    required this.wrongCount,
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
            AvatarSquircle.xs(name: student.displayName),
            const SizedBox(width: AppSpacing.sm),
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
            const SizedBox(width: AppSpacing.xs),
            Icon(LucideIcons.chevronRight,
                size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
