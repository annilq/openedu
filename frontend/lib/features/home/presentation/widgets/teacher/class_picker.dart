import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/domain/models/class_model.dart';
import '../../../../classes/providers/classes_provider.dart';

/// 多选班级：从 [classesRepositoryProvider] 拉取本教师班级，勾选后返回**完整**选中集合。
///
/// 返回空列表表示取消。
Future<List<ClassModel>> pickClasses(
  BuildContext context,
  WidgetRef ref, {
  List<String> initialSelectedIds = const [],
}) async {
  // 未来在弹窗外创建一次，避免 FutureBuilder 每次重建重发请求。
  final future = ref.read(classesRepositoryProvider).getClasses();
  final picked = await showShadDialog<List<ClassModel>>(
    context: context,
    builder: (ctx) => ShadDialog.alert(
      title: const Text('选择班级'),
      child: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: _ClassesPicker(
          future: future,
          initialSelectedIds: initialSelectedIds,
        ),
      ),
    ),
  );
  return picked ?? [];
}

class _ClassesPicker extends StatefulWidget {
  final Future<List<ClassModel>> future;
  final List<String> initialSelectedIds;
  const _ClassesPicker({
    required this.future,
    required this.initialSelectedIds,
  });

  @override
  State<_ClassesPicker> createState() => _ClassesPickerState();
}

class _ClassesPickerState extends State<_ClassesPicker> {
  final Set<String> _chosen = {};

  @override
  void initState() {
    super.initState();
    _chosen.addAll(widget.initialSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    return FutureBuilder<List<ClassModel>>(
      future: widget.future,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const AppLoading();
        }
        if (snap.hasError) {
          return AppError(
            message: '班级加载失败',
            onRetry: () => setState(() {}),
          );
        }
        final classes = snap.data!;
        if (classes.isEmpty) {
          return AppEmptyState(
            icon: LucideIcons.users,
            title: '还没有班级',
            message: '先在「学生」中创建班级，再回来选择。',
          );
        }
        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: classes.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (_, i) {
                  final cl = classes[i];
                  final on = _chosen.contains(cl.id);
                  return AppFocusableAction(
                    onTap: () => setState(() {
                      if (on) {
                        _chosen.remove(cl.id);
                      } else {
                        _chosen.add(cl.id);
                      }
                    }),
                    hoverHighlight: true,
                    semanticLabel: '${on ? "取消" : "选择"}${cl.name}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: app.outline)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            on ? LucideIcons.check : LucideIcons.circle,
                            size: 16,
                            color: on
                                ? app.primary
                                : app.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(cl.name, style: text.bodyMedium),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.only(right: AppSpacing.sm),
                            child: Text(
                              '${cl.grade}年级 · ${cl.studentCount}人',
                              style: text.labelSmall
                                  ?.copyWith(color: app.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(
                    classes
                        .where((cl) => _chosen.contains(cl.id))
                        .toList(),
                  ),
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
