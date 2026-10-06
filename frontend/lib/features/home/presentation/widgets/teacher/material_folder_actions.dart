import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../materials/domain/repositories/material_library_repository.dart';
import '../../../../materials/providers/material_library_provider.dart';

/// 资料库目录操作：选择目标目录（移动到）/ 编辑目录（重命名 + 改元数据）。
///
/// 抽到这里是为了不让 [MaterialLibraryView] 越过 400 行（ADR-0058）。对话框复用
/// 设计系统的 `AppTheme` 令牌与 `AppFocusableAction`（键盘可达 + 焦点环，ADR-0046）。

/// 选择目标目录（「移动到」）。
///
/// 树形列出全部目录 + 顶部「根目录 / 全部」选项（返回 null）。[excludeFolderId]
/// 用于移动目录自身时排除其子树，防止把目录挂进自己的子孙成环（后端也有环检测兜底）。
Future<String?> showFolderPicker(
  BuildContext context, {
  required List<MaterialFolderModel> folders,
  String? excludeFolderId,
}) async {
  final app = AppTheme.colorsOf(context);
  final text = AppTheme.textOf(context);

  // 子树排除集合：自身 + 全部后代。
  final excluded = <String>{};
  if (excludeFolderId != null) {
    excluded.add(excludeFolderId);
    final queue = <String>[excludeFolderId];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final f in folders) {
        if (f.teacherFolderId == cur && !excluded.contains(f.id)) {
          excluded.add(f.id);
          queue.add(f.id);
        }
      }
    }
  }

  final byId = {for (final f in folders) f.id: f};
  final studentsOf = <String?, List<MaterialFolderModel>>{};
  for (final f in folders) {
    if (excluded.contains(f.id)) continue;
    studentsOf.putIfAbsent(f.teacherFolderId, () => []).add(f);
  }

  int depthOf(String id) {
    var d = 0;
    var cursor = byId[id]?.teacherFolderId;
    while (cursor != null && byId.containsKey(cursor)) {
      d += 1;
      cursor = byId[cursor]?.teacherFolderId;
    }
    return d;
  }

  Widget node(MaterialFolderModel f) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFocusableAction(
            onTap: () => Navigator.of(context).pop(f.id),
            semanticLabel: '移动到目录 ${f.name}',
            hoverHighlight: true,
            child: Padding(
              padding: EdgeInsets.only(
                left: 8.0 + depthOf(f.id) * 16.0,
                top: 6,
                bottom: 6,
              ),
              child: Text(f.name, style: text.bodyMedium),
            ),
          ),
          for (final c in studentsOf[f.id] ?? const <MaterialFolderModel>[])
            node(c),
        ],
      );

  final rootChildren = studentsOf[null] ?? const <MaterialFolderModel>[];

  return showShadDialog<String?>(
    context: context,
    barrierColor: app.scrim,
    builder: (ctx) => ShadDialog(
      closeIcon: const SizedBox.shrink(),
      title: const Text('选择目录'),
      child: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppFocusableAction(
                onTap: () => Navigator.of(ctx).pop(null),
                semanticLabel: '移动到根目录',
                hoverHighlight: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '（根目录 / 全部）',
                    style: text.bodyMedium?.copyWith(color: app.accent),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              for (final f in rootChildren) node(f),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 编辑目录：重命名 + 改学科 / 年级 / 学期。返回 null = 取消。
Future<({String name, String? subject, int? grade, String? semester})?>
    showFolderEditDialog(
  BuildContext context, {
  required MaterialFolderModel folder,
}) async {
  final app = AppTheme.colorsOf(context);
  final text = AppTheme.textOf(context);
  final nameCtrl = TextEditingController(text: folder.name);
  String? subject = folder.subject;
  int? grade = folder.grade;
  String? semester = folder.semester;

  return showShadDialog<
      ({String name, String? subject, int? grade, String? semester})?>(
    context: context,
    barrierColor: app.scrim,
    builder: (ctx) => StatefulBuilder(
      builder: (bctx, setState) => ShadDialog(
        closeIcon: const SizedBox.shrink(),
        title: const Text('编辑目录'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(label: '目录名', controller: nameCtrl),
            const SizedBox(height: AppSpacing.md),
            AppPickerField<String>(
              label: '学科（可选）',
              values: const ['数学', '语文', '英语'],
              labels: const ['数学', '语文', '英语'],
              value: subject,
              onChanged: (v) => setState(() => subject = v),
            ),
            const SizedBox(height: AppSpacing.md),
            AppPickerField<int>(
              label: '年级（可选）',
              values: List.generate(9, (i) => i + 1),
              labels: List.generate(9, (i) => '${i + 1}年级'),
              value: grade,
              onChanged: (v) => setState(() => grade = v),
            ),
            const SizedBox(height: AppSpacing.md),
            AppPickerField<String>(
              label: '学期（可选）',
              values: const ['上学期', '下学期'],
              labels: const ['上学期', '下学期'],
              value: semester,
              onChanged: (v) => setState(() => semester = v),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text(
                    '取消',
                    style: text.labelMedium?.copyWith(color: app.onSurface),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ShadButton(
                  onPressed: () => Navigator.of(ctx).pop((
                    name: nameCtrl.text.trim().isEmpty
                        ? folder.name
                        : nameCtrl.text.trim(),
                    subject: subject,
                    grade: grade,
                    semester: semester,
                  )),
                  child: Text(
                    '保存',
                    style: text.labelMedium?.copyWith(color: app.onPrimary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 资料「移动到」：弹目录选择器 → 调 provider。
Future<void> moveMaterialToFolder(
  BuildContext context,
  WidgetRef ref,
  MaterialItemModel mat,
) async {
  final folders = ref.read(materialLibraryNotifierProvider).folders;
  final target = await showFolderPicker(context, folders: folders);
  if (target == null || target == mat.folderId) return;
  await ref
      .read(materialLibraryNotifierProvider.notifier)
      .moveMaterial(mat.id, target);
}

/// 目录「编辑 / 重命名」。
Future<void> editFolderDialog(
  BuildContext context,
  WidgetRef ref,
  MaterialFolderModel folder,
) async {
  final res = await showFolderEditDialog(context, folder: folder);
  if (res == null) return;
  await ref.read(materialLibraryNotifierProvider.notifier).renameFolder(
        folder.id,
        name: res.name,
        subject: res.subject,
        grade: res.grade,
        semester: res.semester,
      );
}

/// 目录「移动到」：弹目录选择器（排除自身子树）→ 调 provider。
Future<void> moveFolderTo(
  BuildContext context,
  WidgetRef ref,
  MaterialFolderModel folder,
) async {
  final folders = ref.read(materialLibraryNotifierProvider).folders;
  final target =
      await showFolderPicker(context, folders: folders, excludeFolderId: folder.id);
  if (target == null) return;
  await ref
      .read(materialLibraryNotifierProvider.notifier)
      .moveFolder(folder.id, target);
}
