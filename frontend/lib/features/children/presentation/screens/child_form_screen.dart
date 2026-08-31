import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../domain/providers/children_provider.dart';
import '../providers/children_notifier.dart';
import '../widgets/interest_picker.dart';

/// 娃娃资料表单模式：创建 or 编辑（WF-5，新增与编辑共用同一页）。
enum ChildFormMode { create, edit }

/// 家长端：创建 / 编辑娃娃资料页（F-102 + WF-5）。
///
/// - create：昵称/账号/密码/年级/兴趣，提交走 createChild。
/// - edit：回填昵称/年级/兴趣；账号与密码锁定不可编辑（避免改登录凭证），
///   提交走 updateChild（仅 display_name/grade/interests）。
/// 保存成功后调用 [onSaved]（由调用方负责刷新列表与关闭页面）。
class ChildFormScreen extends ConsumerStatefulWidget {
  final ChildFormMode mode;
  final UserModel? child; // edit 时传入
  final void Function(UserModel saved)? onSaved;

  const ChildFormScreen({
    super.key,
    required this.mode,
    this.child,
    this.onSaved,
  });

  @override
  ConsumerState<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends ConsumerState<ChildFormScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  int _grade = 2;
  InterestsModel? _interests;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.mode == ChildFormMode.edit;

  @override
  void initState() {
    super.initState();
    if (_isEdit && widget.child != null) {
      final c = widget.child!;
      _nameCtrl.text = c.displayName;
      _usernameCtrl.text = c.username;
      _grade = c.grade ?? 2;
      _interests = c.interests;
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
      // 编辑：仅昵称/年级/兴趣可改，账号密码锁定。
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

    final notifier = ref.read(childrenNotifierProvider.notifier);
    UserModel? saved;
    if (_isEdit && widget.child != null) {
      saved = await notifier.updateChild(
        childId: widget.child!.id,
        displayName: name,
        grade: _grade,
        interests: _interests,
      );
    } else {
      saved = await notifier.createChild(
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        displayName: name,
        grade: _grade,
        interests: _interests,
      );
    }

    if (!mounted) return;
    if (saved != null) {
      widget.onSaved?.call(saved);
      return;
    }
    final state = ref.read(childrenNotifierProvider);
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
    final title = _isEdit ? '编辑娃娃资料' : '添加娃娃账号';
    return SizedBox.expand(
      child: ColoredBox(
        color: app.surface,
        child: Column(
          children: [
            AppTopBar(title: title, showBack: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTextField(
                      label: '娃娃昵称（例如：大宝）',
                      controller: _nameCtrl,
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
                      _LockedField(label: '登录账号（不可修改）', value: _usernameCtrl.text),
                    AppPickerField<int>(
                      label: '年级',
                      values: List.generate(6, (i) => i + 1),
                      labels: List.generate(6, (i) => '${i + 1} 年级'),
                      value: _grade,
                      onChanged: (v) => setState(() => _grade = v),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Container(height: 1, color: app.outline),
                    const SizedBox(height: AppSpacing.lg),
                    InterestPicker(
                      initial: _interests,
                      onChanged: (v) => setState(() => _interests = v),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_error != null) ...[
                      Text(_error!, style: TextStyle(color: app.error)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    AppPrimaryButton(
                      label: _isEdit ? '保存修改' : '创建娃娃账号',
                      onPressed: _submitting ? null : _submit,
                      loading: _submitting,
                    ),
                  ],
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
            border: Border.all(color: app.outline),
          ),
          child: Text(value, style: text.bodyLarge),
        ),
      ],
    );
  }
}
