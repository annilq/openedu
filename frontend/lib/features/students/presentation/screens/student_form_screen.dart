import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:kids_learn/features/classes/providers/classes_provider.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_loading.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../providers/students_provider.dart';
import '../providers/students_notifier.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_card.dart';

/// 学生资料表单模式：创建 or 编辑（WF-5，新增与编辑共用同一页）。
enum ChildFormMode { create, edit }

/// 教师端：创建 / 编辑学生资料页（F-102 + WF-5）。
///
/// - create：昵称/账号/密码，提交走 createChild。
/// - edit：回填昵称；账号与密码锁定不可编辑（避免改登录凭证），
///   提交走 updateChild（仅 display_name）。
/// 学生年级已改由所属班级承载（ADR-0086 修正），本表单不再采集年级。
/// 保存成功后调用 [onSaved]（由调用方负责刷新列表与关闭页面）。
class StudentFormScreen extends ConsumerStatefulWidget {
  final ChildFormMode mode;
  final UserModel? child; // edit 时传入
  final void Function(UserModel saved)? onSaved;

  /// 下钻页（ADR-0086 ticket 06）内置入口创建时，预填归属班级；为 null 走原有全量逻辑。
  final String? classId;

  /// 覆盖层场景（如 home_screen 的编辑层/创建页，未走 Navigator.push）的返回行为。
  /// 为 null 时由 [AppTopBar] 走默认 [Navigator.maybePop]。
  final VoidCallback? onBack;

  const StudentFormScreen({
    super.key,
    required this.mode,
    this.child,
    this.onSaved,
    this.classId,
    this.onBack,
  });

  @override
  ConsumerState<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends ConsumerState<StudentFormScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  /// 班级列表（用于创建时指定归属班级）；编辑时只读展示当前班级。
  List<ClassModel> _classes = const [];
  bool _loadingClasses = false;
  ClassModel? _selectedClass;

  bool get _isEdit => widget.mode == ChildFormMode.edit;

  /// 编辑态展示用：当前学生所属班级名（按 [UserModel.classId] 反查）。
  String get _currentClassName {
    final id = widget.child?.classId;
    if (id == null) return '未分班';
    return _classes.where((c) => c.id == id).firstOrNull?.name ?? '未知班级';
  }

  @override
  void initState() {
    super.initState();
    if (_isEdit && widget.child != null) {
      final c = widget.child!;
      _nameCtrl.text = c.displayName;
      _usernameCtrl.text = c.username;
    }
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _loadingClasses = true);
    try {
      final classes = await ref.read(classesRepositoryProvider).getClasses();
      if (!mounted) return;
      ClassModel? preset;
      if (widget.classId != null) {
        preset = classes.where((c) => c.id == widget.classId).firstOrNull;
      }
      setState(() {
        _classes = classes;
        _selectedClass = preset;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _classes = const []);
    } finally {
      if (mounted) setState(() => _loadingClasses = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final name = _nameCtrl.text.trim();

    if (_isEdit) {
      // 编辑：仅昵称可改，账号密码锁定。
      if (name.isEmpty) {
        setState(() => _error = '昵称不能为空');
        return;
      }
    } else {
      final username = _usernameCtrl.text.trim();
      final password = _passwordCtrl.text;
      if (name.isEmpty || username.isEmpty || password.trim().isEmpty) {
        setState(() => _error = '昵称、账号和密码都不能为空');
        return;
      }
      if (password.length < 4) {
        setState(() => _error = '密码至少 4 位');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final notifier = ref.read(studentsNotifierProvider.notifier);
    UserModel? saved;
    if (_isEdit && widget.child != null) {
      saved = await notifier.updateChild(
        studentId: widget.child!.id,
        displayName: name,
      );
    } else {
      saved = await notifier.createChild(
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        displayName: name,
        classId: _selectedClass?.id,
      );
    }

    if (!mounted) return;
    if (saved != null) {
      widget.onSaved?.call(saved);
      return;
    }
    final state = ref.read(studentsNotifierProvider);
    setState(() {
      _submitting = false;
      if (state is ChildrenError) _error = _friendlyError(state.message);
    });
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('registered') ||
        lower.contains('已注册') ||
        lower.contains('重复')) {
      return '这个账号已被使用，换一个账号名试试';
    }
    return '保存失败，请稍后重试；如果可能已保存成功，请返回列表刷新查看';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final title = _isEdit ? '编辑学生资料' : '添加学生账号';
    return SizedBox.expand(
      child: ColoredBox(
        color: app.surface,
        child: Column(
          children: [
            AppTopBar(title: title, showBack: true, onBack: widget.onBack),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md,
                    AppSpacing.lg, AppSpacing.xl2),
                child: PopIn(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppTextField(
                          label: '学生昵称（例如：大宝）',
                          controller: _nameCtrl,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        // 归属班级：创建时可指定（含从班级下钻页预填）；编辑态仅展示，
                        // 改班级请到学生列表行内「调整班级」（后端走 batchReassign）。
                        if (_isEdit)
                          _LockedField(
                            label: '所属班级（不可在此修改）',
                            value: _currentClassName,
                          )
                        else if (_loadingClasses)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                            child: AppLoading(),
                          )
                        else
                          AppPickerField<ClassModel>(
                            label: '所属班级',
                            values: _classes,
                            labels: _classes.map((c) => c.name).toList(),
                            value: _selectedClass,
                            onChanged: (c) => setState(() => _selectedClass = c),
                            placeholder: '不分配（未分班）',
                          ),
                        const SizedBox(height: AppSpacing.lg),
                        if (!_isEdit) ...[
                          AppTextField(
                            label: '登录账号（唯一，例如：dabao）',
                            controller: _usernameCtrl,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AppTextField(
                            label: '密码（至少 4 位）',
                            controller: _passwordCtrl,
                            obscureText: true,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ] else
                          _LockedField(
                              label: '登录账号（不可修改）', value: _usernameCtrl.text),
                        if (_error != null) ...[
                          Text(_error!, style: TextStyle(color: app.error)),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        AppPrimaryButton(
                          label: _isEdit ? '保存修改' : '创建学生账号',
                          onPressed: _submitting ? null : _submit,
                          loading: _submitting,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 编辑态展示锁定字段（账号密码不可改）。
class _LockedField extends StatelessWidget {
  final String label;
  final String value;
  const _LockedField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: text.labelMedium?.copyWith(color: app.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: app.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.bubble),
            border: Border.all(
              color: AppBrutal.ink,
              width: AppElevation.borderWidth,
            ),
          ),
          child: Text(value, style: text.bodyLarge),
        ),
      ],
    );
  }
}
