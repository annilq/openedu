import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:file_picker/file_picker.dart';

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
import '../../../../shared/widgets/app_focusable_action.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/class_picker.dart';
import '../providers/student_management_notifier.dart';
import '../../providers/student_management_provider.dart';
import '../widgets/student_import_sheet.dart';

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

  /// 顶部「添加学生」入口（原侧栏选择器菜单移除后，新增学生改由这里发起）。
  final VoidCallback? onAddStudent;

  /// 班级下钻页（ADR-0086 ticket 04）：非空时只加载该班学生、隐藏筛选 chip、
  /// 标题含班级名、显示返回按钮。
  final String? classId;

  /// 下钻页标题用的班级名（由下钻发起方直传，不写全局状态）。
  final String? className;

  /// 下钻页返回落点（回到班级管理列表）。全量视图为 null，不显示返回按钮。
  final VoidCallback? onBack;

  const StudentManagementScreen({
    super.key,
    required this.onOpenStudent,
    this.onAddStudent,
    this.classId,
    this.className,
    this.onBack,
  });

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

  /// 导入中（禁用导入按钮，避免重复上传）。
  bool _importing = false;

  /// 模板下载中（禁用下载按钮，避免重复请求）。
  bool _downloadingTemplate = false;

  /// 最近一次导入结果，非 null 时弹出结果浮层（ticket 06）。
  StudentImportResultModel? _importResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // 下钻页（classId != null）只加载该班学生；全量视图传 null。
        ref
            .read(studentManagementProvider.notifier)
            .load(classId: widget.classId);
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

  /// 行内「调整班级」：拉起单班级选择器（预选当前班级），选中后对该学生单独
  /// 调 [batchReassign]。返回 `null` 表示取消（不改）；id 为空 = 显式置为未分班。
  ///
  /// 班级清单取本页已加载的 [StudentManagementLoaded.classes]，不再回源拉一次。
  Future<void> _adjustClass(String studentId) async {
    final state = ref.read(studentManagementProvider);
    if (state is! StudentManagementLoaded) return;
    final currentClassId = state.students
        .where((s) => s.id == studentId)
        .firstOrNull
        ?.classId;
    final picked = await pickSingleClass(
      context,
      classes: Future<List<ClassModel>>.value(state.classes),
      initialClassId: currentClassId,
    );
    if (!mounted || picked == null) return; // 取消，不改
    final targetClassId = picked.id.isEmpty ? null : picked.id;
    if (targetClassId == currentClassId) {
      AppToast.show(context, '该学生已在此班级');
      return;
    }
    try {
      await ref.read(studentManagementProvider.notifier).batchReassign(
            classId: targetClassId,
            studentIds: [studentId],
          );
      if (mounted) {
        AppToast.show(
          context,
          targetClassId == null
              ? '已调整为未分班'
              : '已调整到「${picked.name}」',
        );
      }
    } catch (e) {
      if (mounted) AppToast.error(context, e);
    }
  }

  Future<void> _pickAndImport() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (files.isEmpty) return;
    final file = files.single;
    late final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      if (mounted) AppToast.error(context, Exception('无法读取该文件'));
      return;
    }
    setState(() => _importing = true);
    try {
      final res = await ref
          .read(studentManagementProvider.notifier)
          .importStudents(bytes: bytes, filename: file.name, classId: widget.classId);
      if (mounted) setState(() => _importResult = res);
    } catch (e) {
      if (mounted) AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 下载学生导入模板（方案A）：拉取 xlsx 字节后交由系统保存面板让用户选落盘位置，
  /// 复用已有的 file_picker（saveFile），不引入新依赖。取消保存不提示。
  Future<void> _downloadTemplate() async {
    setState(() => _downloadingTemplate = true);
    try {
      final bytes = await ref
          .read(studentManagementProvider.notifier)
          .downloadImportTemplate();
      final uri = await FilePicker.saveFile(
        dialogTitle: '保存学生导入模板',
        fileName: 'student_import_template.xlsx',
        bytes: bytes,
      );
      final path = uri?.path;
      if (mounted && path != null) {
        AppToast.show(context, '模板已保存：$path');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
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
              onAddStudent: widget.onAddStudent,
              onImport: _importing ? null : _pickAndImport,
              onDownloadTemplate:
                  _downloadingTemplate ? null : _downloadTemplate,
              titleOverride: widget.className != null
                  ? '${widget.className} · '
                      '${_classHeadcount(state, widget.classId) ?? students.length} 人'
                  : null,
              onBack: widget.onBack,
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
                  // 下钻页（classId != null）已是某个班内部，隐藏「全部/各班/未分班」筛选。
                  if (state is StudentManagementLoaded && widget.classId == null)
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
                onRetry: () => ref
                    .read(studentManagementProvider.notifier)
                    .load(classId: widget.classId),
                onOpenStudent: widget.onOpenStudent,
                onAdjustClass: _adjustClass,
                buildRows: _buildRows,
                classId: widget.classId,
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
        if (_importResult != null)
          StudentImportSheet(
            result: _importResult!,
            onDismiss: () => setState(() => _importResult = null),
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
  final VoidCallback? onAddStudent;
  final VoidCallback? onImport;
  final VoidCallback? onDownloadTemplate;

  /// 下钻页标题覆盖（含班级名 + 人数）；为空时回退「学生管理」+ 徽标。
  final String? titleOverride;

  /// 下钻页返回按钮（回到班级管理列表）；全量视图为 null。
  final VoidCallback? onBack;

  const _PageHeader({
    required this.state,
    required this.selecting,
    required this.selectedCount,
    required this.visibleCount,
    required this.onToggleSelecting,
    required this.onSelectAll,
    this.onAddStudent,
    this.onImport,
    this.onDownloadTemplate,
    this.titleOverride,
    this.onBack,
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
          if (onBack != null)
            AppIconAction(
              icon: LucideIcons.arrowLeft,
              semanticLabel: '返回',
              onPressed: onBack,
            ),
          Text(titleOverride ?? '学生管理', style: text.titleLarge),
          const SizedBox(width: AppSpacing.sm),
          if (!selecting && total != null && titleOverride == null)
            AppBadge(
              label: '$total 人',
              background: scheme.surfaceSunken,
              foreground: scheme.onSurfaceVariant,
            ),
          const Spacer(),
          if (onAddStudent != null)
            AppIconAction(
              icon: LucideIcons.userPlus,
              semanticLabel: '添加学生',
              onPressed: onAddStudent,
            ),
          AppIconAction(
            icon: LucideIcons.download,
            semanticLabel: '下载导入模板',
            onPressed: onDownloadTemplate,
          ),
          AppIconAction(
            icon: LucideIcons.upload,
            semanticLabel: '批量导入',
            onPressed: onImport,
          ),
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
          child: AppFocusableAction(
            onTap: onDismiss,
            semanticLabel: '关闭',
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
                          child: Text('还没有班级，请先在「班级管理」里新建。',
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
  final void Function(String studentId) onAdjustClass;
  final List<_RowItem> Function(List<UserModel>, List<ClassModel>) buildRows;

  /// 下钻页（classId != null）：已是某个班内部，直接平铺学生，不再分组。
  final String? classId;

  const _Body({
    required this.state,
    required this.filter,
    required this.selecting,
    required this.selected,
    required this.onToggleSelect,
    required this.onRetry,
    required this.onOpenStudent,
    required this.onAdjustClass,
    required this.buildRows,
    this.classId,
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
          message: '点击右上角「添加学生」或批量导入花名册，学生会出现在这里。',
        ),
      );
    }

    // 下钻页：不套分组头，直接平铺该班学生。
    if (classId != null) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: loaded.students.length,
        itemBuilder: (context, i) => _StudentTile(
          student: loaded.students[i],
          wrongCount: loaded.wrongCounts[loaded.students[i].id] ?? 0,
          selecting: selecting,
          selected: selected.contains(loaded.students[i].id),
          onTap: selecting
              ? () => onToggleSelect(loaded.students[i].id)
              : () => onOpenStudent(loaded.students[i].id),
          onAdjustClass: onAdjustClass,
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
          onAdjustClass: onAdjustClass,
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
  final void Function(String studentId)? onAdjustClass;

  const _StudentTile({
    required this.student,
    required this.wrongCount,
    this.selecting = false,
    this.selected = false,
    required this.onTap,
    this.onAdjustClass,
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
            if (!selecting)
              AppIconAction(
                icon: LucideIcons.school,
                semanticLabel: '调整班级',
                onPressed: onAdjustClass != null
                    ? () => onAdjustClass!(student.id)
                    : null,
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

/// 班级真实人数（[ClassModel.studentCount]），用于下钻标题展示「N 人」。
///
/// 下钻页 [getStudents] 会按关键词过滤，[state.students] 是过滤后的子集；
/// 标题里的「N 人」应按规范表示班级规模，故从 [StudentManagementLoaded.classes]
/// 取对应班级的 headcount，搜索时也不随之缩水。找不到该班级时回退到列表长度。
int? _classHeadcount(StudentManagementState state, String? classId) {
  if (classId == null || state is! StudentManagementLoaded) return null;
  for (final c in state.classes) {
    if (c.id == classId) return c.studentCount;
  }
  return null;
}
