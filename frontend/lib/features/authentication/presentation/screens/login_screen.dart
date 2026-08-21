import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_inputs.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../domain/providers/auth_provider.dart';
import '../providers/auth_notifier.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback? onLoginSuccess;
  const LoginScreen({super.key, this.onLoginSuccess});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  String? _usernameError;
  String? _passwordError;
  String? _displayNameError;
  bool _isRegister = false;

  bool _submitValid() {
    final usernameOk = _username.text.isNotEmpty;
    final passwordOk = _password.text.length >= 4;
    final displayNameOk = !_isRegister || _displayName.text.isNotEmpty;
    setState(() {
      _usernameError = usernameOk ? null : '请输入用户名';
      _passwordError = passwordOk ? null : '密码至少4位';
      _displayNameError = displayNameOk ? null : '请输入昵称';
    });
    return usernameOk && passwordOk && displayNameOk;
  }

  void _submit() {
    if (!_submitValid()) return;
    ref.read(authNotifierProvider.notifier).register(
          username: _username.text,
          password: _password.text,
          displayName: _displayName.text,
        );
  }

  void _login() {
    if (!_submitValid()) return;
    ref.read(authNotifierProvider.notifier).login(
          username: _username.text,
          password: _password.text,
        );
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState is AuthLoading;

    // 监听状态变化
    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      if (next is AuthError) {
        AppToast.error(context, next.message);
      }
      if (next is AuthSuccess) {
        widget.onLoginSuccess?.call();
      }
    });

    return CupertinoPageScaffold(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand area
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: app.primaryContainer,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(
                        CupertinoIcons.book,
                        size: 52,
                        color: app.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: Text(
                      '娃娃学习',
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Center(
                    child: Text(
                      _isRegister ? '创建家长账号，和孩子一起成长' : '欢迎回来，继续今天的学习',
                      style: text.bodyLarge?.copyWith(
                        color: app.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(height: AppSpacing.xxl * 1.2),

                  // Form card
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: app.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: app.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _isRegister ? '注册' : '登录',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AppTextField(
                          label: '用户名',
                          controller: _username,
                          prefixIcon: CupertinoIcons.person,
                          errorText: _usernameError,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppTextField(
                          label: '密码',
                          controller: _password,
                          obscureText: true,
                          prefixIcon: CupertinoIcons.lock,
                          errorText: _passwordError,
                        ),
                        if (_isRegister) ...[
                          const SizedBox(height: AppSpacing.md),
                          AppTextField(
                            label: '昵称',
                            controller: _displayName,
                            prefixIcon: CupertinoIcons.person_crop_circle,
                            errorText: _displayNameError,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        AppPrimaryButton(
                          label: _isRegister ? '注册并进入' : '登录',
                          onPressed: isLoading
                              ? null
                              : (_isRegister ? _submit : _login),
                          loading: isLoading,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        CupertinoButton(
                          onPressed: isLoading
                              ? null
                              : () {
                                  setState(() => _isRegister = !_isRegister);
                                  ref
                                      .read(authNotifierProvider.notifier)
                                      .reset();
                                },
                          child: Text(
                            _isRegister ? '已有账号？去登录' : '没有账号？注册家长账号',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: Text(
                      '护眼模式 · 适合孩子的舒适界面',
                      style: text.bodySmall?.copyWith(
                        color: app.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}