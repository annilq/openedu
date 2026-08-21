import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../domain/providers/auth_provider.dart';
import '../providers/auth_notifier.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback? onLoginSuccess;
  const LoginScreen({super.key, this.onLoginSuccess});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  bool _isRegister = false;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authNotifierProvider.notifier).register(
          username: _username.text,
          password: _password.text,
          displayName: _displayName.text,
        );
  }

  void _login() {
    if (!_formKey.currentState!.validate()) return;
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
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState is AuthLoading;

    // 监听状态变化
    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      if (next is AuthError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            backgroundColor: theme.colorScheme.errorContainer,
            content: Text(
              next.message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        );
      }
      if (next is AuthSuccess) {
        widget.onLoginSuccess?.call();
      }
    });

    return Scaffold(
      body: SafeArea(
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
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(
                        Icons.auto_stories_rounded,
                        size: 52,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: Text(
                      '娃娃学习',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Center(
                    child: Text(
                      _isRegister ? '创建家长账号，和孩子一起成长' : '欢迎回来，继续今天的学习',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(height: AppSpacing.xxl * 1.2),

                  // Form card
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isRegister ? '注册' : '登录',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          TextFormField(
                            controller: _username,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '用户名',
                              prefixIcon: Icon(Icons.person_2_outlined),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? '请输入用户名' : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _password,
                            textInputAction: _isRegister
                                ? TextInputAction.next
                                : TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: '密码',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                            obscureText: true,
                            validator: (v) =>
                                v == null || v.length < 4 ? '密码至少4位' : null,
                          ),
                          if (_isRegister) ...[
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _displayName,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: '昵称',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                              validator: (v) =>
                                  v == null || v.isEmpty ? '请输入昵称' : null,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          FilledButton(
                            onPressed: isLoading
                                ? null
                                : (_isRegister ? _submit : _login),
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.button),
                              ),
                            ),
                            child: isLoading
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: theme.colorScheme.onPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      const Text('处理中…'),
                                    ],
                                  )
                                : Text(
                                    _isRegister ? '注册并进入' : '登录',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextButton(
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
                  ),

                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: Text(
                      '护眼模式 · 适合孩子的舒适界面',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
