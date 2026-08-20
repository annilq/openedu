import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/domain/models/models.dart';

class ProfileScreen extends ConsumerWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              user.displayName.isNotEmpty ? user.displayName[0] : '?',
              style: const TextStyle(fontSize: 36, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(user.displayName,
              style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(user.isParent ? '家长账号' : '${user.grade ?? "?"}年级 · ${user.username}'),
        ),
        const SizedBox(height: 32),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('用户名'),
                trailing: Text(user.username),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('角色'),
                trailing: Text(user.isParent ? '家长' : '娃娃'),
              ),
              if (user.grade != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.grade_outlined),
                  title: const Text('年级'),
                  trailing: Text('${user.grade}年级'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('退出登录'),
                  content: const Text('确定要退出吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onLogout();
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('退出登录'),
          ),
        ),
      ],
    );
  }
}
