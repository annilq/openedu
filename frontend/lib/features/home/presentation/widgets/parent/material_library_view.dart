import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_actions.dart';
import '../../../../../shared/widgets/app_buttons.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_dialog.dart';
import '../../../../../shared/widgets/app_empty_state.dart';
import '../../../../../shared/widgets/app_focusable_action.dart';
import '../../../../../shared/widgets/app_inputs.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_scroll_page.dart';
import '../../../../../shared/widgets/app_section_title.dart';
import '../../../../../shared/widgets/app_tags.dart';
import '../../../../../shared/widgets/app_toast.dart';
import '../../../../materials/domain/repositories/material_library_repository.dart';
import '../../../../materials/providers/material_library_provider.dart';
import '../../../providers/knowledge_manage_provider.dart';
import 'material_folder_actions.dart';
import 'material_knowledge_manage_view.dart';

/// 资料库页（ADR-0055 B6）：网盘式目录 + 上传 + 手动向量化 + 状态徽标。
///
/// 两个视图用分段切换：**资料**（目录/资料/向量化）与**知识点管理**
/// （按学科×年级查看涌现目录、勾选待审/骨架条目并批量确认转正，ADR-0055 §4）。
class MaterialLibraryView extends ConsumerStatefulWidget {
  const MaterialLibraryView({super.key});

  @override
  ConsumerState<MaterialLibraryView> createState() =>
      _MaterialLibraryViewState();
}

class _MaterialLibraryViewState extends ConsumerState<MaterialLibraryView> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    // 进入资料库页即拉取根目录与一级目录。必须推迟到首帧之后：load() 会同步把
    // state.loading 置 true（notifyListeners），若在 initState/build 期间直接改被本页
    // watch 的 provider，Riverpod 会抛「modify provider during build」。addPostFrameCallback
    // 等本帧绘制完再触发，避开该限制（ADR-0055 B6 修复）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(materialLibraryNotifierProvider.notifier).load();
    });
  }

  Future<void> _pickAndUpload() async {
    // file_picker 13：静态方法，取消返回空列表；桌面端用 readAsBytes 拿字节。
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'txt', 'md'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await ref.read(materialLibraryNotifierProvider.notifier).upload(
          filename: file.name,
          bytes: bytes,
        );
  }

  Future<void> _newFolder() async {
    final nameCtrl = TextEditingController();
    String? subject;
    int? grade;
    String? semester;
    final confirmed = await AppDialog.confirm(
      context,
      title: const Text('新建目录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(label: '目录名', controller: nameCtrl),
          const SizedBox(height: AppSpacing.md),
          AppPickerField<String>(
            label: '学科（可选，子项继承）',
            values: const ['数学', '语文', '英语'],
            labels: const ['数学', '语文', '英语'],
            value: subject,
            onChanged: (v) => subject = v,
          ),
          const SizedBox(height: AppSpacing.md),
          AppPickerField<int>(
            label: '年级（可选，子项继承）',
            values: List.generate(9, (i) => i + 1),
            labels: List.generate(9, (i) => '${i + 1}年级'),
            value: grade,
            onChanged: (v) => grade = v,
          ),
          const SizedBox(height: AppSpacing.md),
          AppPickerField<String>(
            label: '学期（可选，子项继承）',
            values: const ['上学期', '下学期'],
            labels: const ['上学期', '下学期'],
            value: semester,
            onChanged: (v) => semester = v,
          ),
        ],
      ),
    );
    final name = nameCtrl.text;
    nameCtrl.dispose();
    if (confirmed != true || !mounted) return;
    await ref.read(materialLibraryNotifierProvider.notifier).createFolder(
          name: name,
          subject: subject,
          grade: grade,
          semester: semester,
        );
  }

  void _switchTab(int idx) {
    if (idx == _tabIndex) return;
    setState(() => _tabIndex = idx);
    // 进入「知识点管理」视图时按需拉一次目录（确保最新待审/骨架状态）。
    if (idx == 1) {
      ref.read(knowledgeManageProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final libState = ref.watch(materialLibraryNotifierProvider);
    ref.listen(materialLibraryNotifierProvider, (_, next) {
      if (next.notice != null) {
        AppToast.show(context, next.notice!);
        // 仅在确有 notice 时消费，否则 state= 会再次同步触发本 listener
        // 形成无限递归（Stack Overflow）。
        ref.read(materialLibraryNotifierProvider.notifier).consumeNotice();
      }
    });
    ref.listen(knowledgeManageProvider, (_, next) {
      if (next.notice != null) {
        AppToast.show(context, next.notice!);
        ref.read(knowledgeManageProvider.notifier).consumeNotice();
      }
    });

    return AppScrollPage(
      children: [
        SectionTitle('资料库'),
        _segmented(),
        const SizedBox(height: AppSpacing.md),
        if (_tabIndex == 0)
          _buildMaterialsCard(libState)
        else
          const MaterialKnowledgeManageView(),
      ],
    );
  }

  /// 分段切换：资料 / 知识点管理。当前项实心高亮，另一项浅底描边（neo-brutalist）。
  Widget _segmented() => Row(
        children: [
          Expanded(child: _segBtn('资料', 0)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _segBtn('知识点管理', 1)),
        ],
      );

  Widget _segBtn(String label, int idx) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final active = _tabIndex == idx;
    return AppFocusableAction(
      onTap: () => _switchTab(idx),
      semanticLabel: '切换到$label',
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? app.primary : app.surfaceRaised,
          border: Border.all(color: app.outline, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Text(
          label,
          style: text.bodyLarge?.copyWith(
            color: active ? app.onPrimary : app.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── 资料视图（目录 + 资料 + 向量化，B6）───────────────────────────────

  Widget _buildMaterialsCard(MaterialLibraryState state) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    // 是否身处目录内（null=根）：header 仅当 inFolder 才显示，回根即消失。
    final bool inFolder = state.currentFolderId != null;
    final current = inFolder ? state.folderById(state.currentFolderId) : null;
    final subfolders = state.folders
        .where((f) => f.parentFolderId == state.currentFolderId)
        .toList();

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              AppPrimaryButton(label: '上传资料', onPressed: _pickAndUpload),
              ShadButton.outline(
                leading: const Icon(LucideIcons.folderPlus, size: 16),
                onPressed: _newFolder,
                child: const Text('新建目录'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(state.error!,
                  style: text.bodySmall?.copyWith(color: app.error)),
            ),
          // 当前目录标题：根目录无返回键（就是默认视图）；子目录左侧「← 返回」回到上层。
          // 返回目标直接用 state.parentFolderId（load 时已写入），不依赖从 folders 反查。
          // inFolder 才是 header 开关——回根（currentFolderId=null）时这道分支必不进。
          if (inFolder && current != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  AppIconAction(
                    icon: LucideIcons.arrowLeft,
                    iconSize: 18,
                    semanticLabel: '返回上层目录',
                    onPressed: () => ref
                        .read(materialLibraryNotifierProvider.notifier)
                        .openFolder(state.parentFolderId),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(current.name,
                        style: text.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          if (state.loading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: AppLoading()),
            )
          else ...[
            ...subfolders.map(_folderRow),
            ...state.materials.map(_materialRow),
            if (subfolders.isEmpty && state.materials.isEmpty)
              AppEmptyState(
                icon: LucideIcons.folderOpen,
                title: current == null ? '这里还没有资料' : '「${current.name}」还是空的',
                message: current == null
                    ? '上传教材、卷子或笔记，向量化后出题时会自动参考'
                    : '上传资料到这个目录，或把已有资料「移动」进来',
              ),
          ],
        ],
      ),
    );
  }

  Widget _folderRow(MaterialFolderModel folder) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final meta = [
      if (folder.subject != null) folder.subject!,
      if (folder.grade != null) '${folder.grade}年级',
      if (folder.semester != null && folder.semester!.isNotEmpty) folder.semester!,
    ].join(' · ');
    // 整行（图标 + 名称 + 计数）都可点进入；右侧重命名/移动/删除是独立按钮，不触发导航。
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: AppFocusableAction(
              hoverHighlight: true,
              onTap: () => ref
                  .read(materialLibraryNotifierProvider.notifier)
                  .openFolder(folder.id),
              semanticLabel: '打开目录 ${folder.name}',
              child: Row(
                children: [
                  const Icon(LucideIcons.folder, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: folder.name),
                      if (meta.isNotEmpty)
                        TextSpan(
                            text: '　$meta',
                            style: text.bodySmall
                                ?.copyWith(color: app.onSurfaceVariant)),
                    ])),
                  ),
                  Text('${folder.materialCount} 份资料',
                      style: text.bodySmall
                          ?.copyWith(color: app.onSurfaceVariant)),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(LucideIcons.chevronRight,
                      size: 16, color: app.onSurfaceVariant),
                ],
              ),
            ),
          ),
          AppTextAction(label: '重命名', onPressed: () => editFolderDialog(context, ref, folder)),
          AppTextAction(label: '移动', onPressed: () => moveFolderTo(context, ref, folder)),
          AppIconAction(
            icon: LucideIcons.trash2,
            iconSize: 16,
            semanticLabel: '删除目录 ${folder.name}',
            onPressed: () => ref
                .read(materialLibraryNotifierProvider.notifier)
                .deleteFolder(folder.id),
          ),
        ],
      ),
    );
  }

  Widget _materialRow(MaterialItemModel mat) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final label = kIndexStateLabels[mat.indexState] ?? mat.indexState;
    final badgeColor = switch (mat.indexState) {
      'ready' => app.primary,
      'failed' => app.error,
      'stale' => app.secondary,
      _ => app.onSurfaceVariant,
    };
    final meta = [
      if (mat.subject != null) mat.subject!,
      if (mat.grade != null) '${mat.grade}年级',
    ].join(' · ');
    // 知识点 chip（ADR-0055 §3）：资料级知识点直接展示，让家长一眼看到
    // 这份资料覆盖了哪些点；空时（如尚未重提取）不占空间。
    final kpChips = mat.knowledgePoints.isEmpty
        ? const <Widget>[]
        : <Widget>[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final kp in mat.knowledgePoints) AppTags.normal(kp),
              ],
            ),
          ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.fileText, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: mat.name),
                    if (meta.isNotEmpty)
                      TextSpan(
                        text: '　$meta',
                        style: text.bodySmall
                            ?.copyWith(color: app.onSurfaceVariant),
                      ),
                  ]),
                ),
              ),
              Text(label,
                  style: text.bodySmall
                      ?.copyWith(color: badgeColor, fontWeight: FontWeight.w700)),
              const SizedBox(width: AppSpacing.sm),
              AppTextAction(label: mat.indexState == 'ready' ? '重新向量化' : '向量化', onPressed: () => ref.read(materialLibraryNotifierProvider.notifier).vectorize(mat.id)),
              AppTextAction(label: '重提取', onPressed: () => ref.read(materialLibraryNotifierProvider.notifier).reextract(mat.id)),
              AppTextAction(label: '移动', onPressed: () => moveMaterialToFolder(context, ref, mat)),
              AppIconAction(icon: LucideIcons.trash2, iconSize: 16, semanticLabel: '删除资料 ${mat.name}', onPressed: () => ref.read(materialLibraryNotifierProvider.notifier).deleteMaterial(mat.id)),
            ],
          ),
          ...kpChips,
        ],
      ),
    );
  }
}
