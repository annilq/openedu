import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../domain/providers/children_provider.dart';
import '../providers/children_notifier.dart';

/// 家长端：创建娃娃账号页（F-102）。
///
/// 字段与后端 `POST /children` 契约一致（children_remote_data_source.dart）：
/// 昵称 display_name / 账号 username（唯一）/ 密码 password（≥4 位）/ 年级 grade（1~6）。
/// 提交成功后 pop(true)，由调用方刷新并选中新娃娃。
class AddChildScreen extends ConsumerStatefulWidget {
  const AddChildScreen({super.key});

  @override
  ConsumerState<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends ConsumerState<AddChildScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  int _grade = 2;
  bool _submitting = false;
  String? _error;

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
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text; // 不 trim：保留用户真实密码（仅校验空白）

    // 前端表单校验
    if (name.isEmpty || username.isEmpty || password.trim().isEmpty) {
      setState(() => _error = '昵称、账号和密码都不能为空');
      return;
    }
    if (password.length < 4) {
      setState(() => _error = '密码至少 4 位');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final created = await ref.read(childrenNotifierProvider.notifier).createChild(
          username: username,
          password: password,
          displayName: name,
          grade: _grade,
        );
    if (!mounted) return;

    if (created != null) {
      // 成功后 notifier 已自动刷新列表；携带新用户 id 返回，供首页定向选中
      Navigator.of(context).pop(created.id);
      return;
    }

    final state = ref.read(childrenNotifierProvider);
    setState(() {
      _submitting = false;
      if (state is ChildrenError) {
        _error = _friendlyError(state.message);
      }
    });
  }

  /// 把后端/底层错误转成家长可读文案。
  /// 注意：dio 层只透出 detail 字符串（不含状态码），按语义匹配即可。
  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('registered') ||
        lower.contains('已注册') ||
        lower.contains('重复')) {
      return '这个账号已被使用，换一个账号名试试';
    }
    // 建号成功但刷新列表失败也会走到这里：提示可能已创建成功
    return '创建失败，请稍后重试；如果账号可能已创建成功，请返回列表刷新查看';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    return SizedBox.expand(
      child: ColoredBox(
        color: app.surface,
        child: Column(
          children: [
            AppTopBar(title: '添加娃娃账号', showBack: true),
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
                    AppPickerField<int>(
                      label: '年级',
                      values: List.generate(6, (i) => i + 1),
                      labels: List.generate(6, (i) => '${i + 1} 年级'),
                      value: _grade,
                      onChanged: (v) => setState(() => _grade = v),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(color: app.error),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    AppPrimaryButton(
                      label: '创建娃娃账号',
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
