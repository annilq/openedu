import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/app_theme.dart';
import 'app_empty_state.dart';
import 'app_error.dart';
import 'app_loading.dart';
import 'app_focusable_action.dart';
import '../domain/models/class_model.dart';

/// 班级选择器：教师端两处复用（发布任务表单的派发班级、学生管理页的行内调整班级）。
///
/// **为什么在 shared/**：原先放在 `features/home/presentation/widgets/teacher/`，
/// 学生管理页横向 import 它就违反了分层单向规则（ADR-0037 R2，守卫见
/// `feature_boundaries_test.dart`）。被两个 feature 复用的能力按规则下沉 shared/，
/// 而不是让 students 反向依赖 home。
///
/// **为什么班级列表由调用方注入**：`shared/` 不得 import `features/`（R1），
/// 而班级取数组合根 `classesRepositoryProvider` 属于 classes feature。故本文件只认
/// [Future] + [ClassModel]（都在 shared/domain），由调用方决定数据从哪来——
/// 副作用是选择器不再绑定具体 repository，也就能脱离 provider 单测。
///
/// 调用方应在弹窗外创建一次 future 再传入，避免 FutureBuilder 每次重建重发请求。
Future<List<ClassModel>> pickClasses(
  BuildContext context, {
  required Future<List<ClassModel>> classes,
  List<String> initialSelectedIds = const [],
}) async {
  final picked = await showShadDialog<List<ClassModel>>(
    context: context,
    builder: (ctx) => ShadDialog.alert(
      title: const Text('选择班级'),
      child: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: _ClassesPicker(
          future: classes,
          initialSelectedIds: initialSelectedIds,
        ),
      ),
    ),
  );
  return picked ?? [];
}

/// 未分班哨兵：区别于「取消对话框」的 `null`，使调用方知道用户**显式**选了未分班。
const ClassModel _unclassedMarker = ClassModel(id: '', name: '未分班', grade: 0);

/// 单选班级：列出 [classes]，选中后返回该 [ClassModel]；
/// 选「不分配（未分班）」返回 [_unclassedMarker]（非 `null`），取消对话框才返回 `null`。
/// 用于学生表单指定归属班级、学生列表行内「调整班级」。
Future<ClassModel?> pickSingleClass(
  BuildContext context, {
  required Future<List<ClassModel>> classes,
  String? initialClassId,
}) async {
  final picked = await showShadDialog<ClassModel?>(
    context: context,
    builder: (ctx) => ShadDialog.alert(
      title: const Text('调整班级'),
      child: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: _SingleClassPicker(
          future: classes,
          initialClassId: initialClassId,
        ),
      ),
    ),
  );
  return picked;
}

class _SingleClassPicker extends StatefulWidget {
  final Future<List<ClassModel>> future;
  final String? initialClassId;
  const _SingleClassPicker({
    required this.future,
    this.initialClassId,
  });

  @override
  State<_SingleClassPicker> createState() => _SingleClassPickerState();
}

class _SingleClassPickerState extends State<_SingleClassPicker> {
  ClassModel? _chosen;

  @override
  void initState() {
    super.initState();
    // 初始选中需等数据回来再解析（id → 对象），故在 builder 里完成。
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
        // 初次解析初始选中：initialClassId 命中预选该班；为 null 表示当前未分班，预选「未分班」。
        _chosen ??= (widget.initialClassId == null
            ? _unclassedMarker
            : classes
                .where((cl) => cl.id == widget.initialClassId)
                .firstOrNull);
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                children: [
                  for (final cl in classes)
                    AppFocusableAction(
                      onTap: () => Navigator.of(context).pop(cl),
                      hoverHighlight: true,
                      semanticLabel: '调整到${cl.name}',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
                        decoration: BoxDecoration(
                          border:
                              Border(bottom: BorderSide(color: app.outline)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _chosen?.id == cl.id
                                  ? LucideIcons.check
                                  : LucideIcons.circle,
                              size: 16,
                              color: _chosen?.id == cl.id
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
                    ),
                  AppFocusableAction(
                    onTap: () => Navigator.of(context).pop(_unclassedMarker),
                    hoverHighlight: true,
                    semanticLabel: '调整为未分班',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: app.outline)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _chosen == _unclassedMarker
                                ? LucideIcons.check
                                : LucideIcons.circle,
                            size: 16,
                            color: _chosen == _unclassedMarker
                                ? app.primary
                                : app.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text('不分配（未分班）',
                                style: text.bodyMedium),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
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
