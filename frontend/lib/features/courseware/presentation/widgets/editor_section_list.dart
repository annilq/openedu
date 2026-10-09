import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_actions.dart';
import '../../../../shared/widgets/app_buttons.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/models/courseware_section.dart';
import '../pages/courseware_section_edit_dialog.dart';

/// 编辑器里的环节列表：支持拖拽重排与多选批量删（ADR-0067 第二轮 T01）。
///
/// ⚠️ 不用 Material 的 `ReorderableListView`（需要 Material 祖先，本仓禁用——App 根是
/// `ShadApp` + `CupertinoApp`）。改用 `Draggable`（拖拽手柄）+ `DragTarget`
/// （每张卡是落点）自实现，零 Material 依赖。
///
/// 重排 / 批量删都通过回调把「新环节序列」交给父级落库（`updateSections` 整体覆盖写），
/// 本 widget 只负责交互与本地选中态，不碰 repository。
class CoursewareEditorSectionList extends ConsumerStatefulWidget {
  const CoursewareEditorSectionList({
    super.key,
    required this.sections,
    required this.onReorder,
    required this.onDeleteSelected,
    required this.onEdit,
    this.knowledgePointId,
    required this.kpName,
    required this.subject,
    required this.grade,
    required this.semester,
  });

  final List<CoursewareSectionModel> sections;
  final ValueChanged<List<CoursewareSectionModel>> onReorder;
  final ValueChanged<List<String>> onDeleteSelected;
  final ValueChanged<CoursewareSectionModel> onEdit;

  /// 课件所属知识点 id（空白环节也能「关联知识点场景」）。null = 孤儿课件，禁用该能力。
  final String? knowledgePointId;
  final String kpName;
  final String subject;
  final int grade;
  final String semester;

  @override
  ConsumerState<CoursewareEditorSectionList> createState() =>
      _CoursewareEditorSectionListState();
}

class _CoursewareEditorSectionListState
    extends ConsumerState<CoursewareEditorSectionList> {
  bool _selecting = false;
  final Set<String> _selected = {};

  void _toggleSelect(String id) => setState(() {
        if (_selected.contains(id)) {
          _selected.remove(id);
        } else {
          _selected.add(id);
        }
      });

  void _exitSelect() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _commitDelete() {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    widget.onDeleteSelected(ids);
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  /// 手动添加环节（courseware-round-3 T04）：打开与编辑同构的空白表单，保存后把新环节
  /// 追加到列表末尾，经 [onReorder]（即 `PUT /{id}/sections` 整体覆盖写）落库。
  ///
  /// 因 T03 已去 kind，空白环节无需 kind 选择器——与「每个环节的内容都是配置选择」一致。
  Future<void> _addSection() async {
    final created = await showCoursewareSectionEditDialog(
      context,
      ref,
      CoursewareSectionModel(), // 空白环节：无 kind、title/话术/素材/场景皆空
      knowledgePointId: widget.knowledgePointId,
      kpName: widget.kpName,
      subject: widget.subject,
      grade: widget.grade,
      semester: widget.semester,
    );
    if (created == null) return; // 用户取消，列表不动
    widget.onReorder([...widget.sections, created]);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.colorsOf(context);
    final text = AppTheme.textOf(context);
    final items = widget.sections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('${items.length} 个讲解环节', style: text.bodyMedium),
              ),
              if (_selecting) ...[
                AppTextAction(label: '取消', onPressed: _exitSelect),
                const SizedBox(width: AppSpacing.sm),
                AppPrimaryButton(
                  label: '删除选中(${_selected.length})',
                  fullWidth: false,
                  onPressed: _selected.isEmpty ? null : _commitDelete,
                ),
              ] else ...[
                AppTextAction(label: '添加环节', onPressed: _addSection),
                const SizedBox(width: AppSpacing.sm),
                AppTextAction(
                  label: '选择',
                  onPressed: items.isEmpty ? null : () => setState(() => _selecting = true),
                ),
              ],
            ],
          ),
        ),
        if (items.isEmpty)
          const SizedBox.shrink()
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) => _item(items, i, app, text),
            ),
          ),
        if (!_selecting && items.isNotEmpty)
          _endDropZone(items),
      ],
    );
  }

  /// 每张卡的落点：dropped 来自 [from]、落到当前 [index] 时重排。
  Widget _item(
    List<CoursewareSectionModel> items,
    int index,
    AppColors app,
    AppText text,
  ) {
    final s = items[index];
    final selected = _selected.contains(s.id);
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) {
        if (d.data == index) return;
        widget.onReorder(reorderCoursewareSections(items, d.data, index));
      },
      builder: (context, _, __) => Row(
        children: [
          if (!_selecting)
            Draggable<int>(
              key: Key('drag-$index'),
              data: index,
              feedback: _gripGhost(app),
              childWhenDragging: _grip(app, faded: true),
              child: _grip(app),
            ),
          Expanded(child: _card(s, selected, app, text)),
        ],
      ),
    );
  }

  /// 列表末尾的落点：拖到此处即排到最末。
  Widget _endDropZone(List<CoursewareSectionModel> items) => DragTarget<int>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) {
          if (d.data == items.length - 1) return;
          widget.onReorder(reorderCoursewareSections(items, d.data, items.length));
        },
        builder: (context, accepted, rejected) => SizedBox(
          height: AppSpacing.xl + AppSpacing.md,
          child: Center(
            child: Icon(
              LucideIcons.gripVertical,
              size: AppSpacing.lg,
              color: accepted.isNotEmpty
                  ? AppTheme.colorsOf(context).primary
                  : AppTheme.colorsOf(context).onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
      );

  Widget _grip(AppColors app, {bool faded = false}) => AppIconAction(
        icon: LucideIcons.gripVertical,
        onPressed: null,
        semanticLabel: '拖拽重排',
        color: faded
            ? app.onSurfaceVariant.withValues(alpha: 0.3)
            : app.onSurfaceVariant,
      );

  Widget _gripGhost(AppColors app) => Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: app.surface,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          boxShadow: [
            BoxShadow(
              color: app.onSurfaceVariant.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(LucideIcons.gripVertical, color: app.primary),
      );

  Widget _card(
    CoursewareSectionModel s,
    bool selected,
    AppColors app,
    AppText text,
  ) {
    // 内容块统一化（T03 去 kind）：不再按 kind 分派，按「填了什么」推断图标与分类标签。
    final IconData icon;
    final String category;
    if (s.resolvedScene != null) {
      icon = LucideIcons.shapes;
      category = '交互讲解';
    } else if (s.resolvedMaterials.isNotEmpty) {
      icon = LucideIcons.images;
      category = '素材展示';
    } else if (s.practice != null) {
      icon = LucideIcons.penLine;
      category = '课堂练习';
    } else {
      icon = LucideIcons.circleHelp;
      category = '讲解';
    }
    final onTap =
        _selecting ? () => _toggleSelect(s.id) : () => widget.onEdit(s);
    return AppCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            if (_selecting)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: AppIconAction(
                  icon: selected ? LucideIcons.check : LucideIcons.circle,
                  onPressed: () => _toggleSelect(s.id),
                  semanticLabel: selected ? '已选中，点按取消' : '选此项',
                  color: selected ? app.primary : app.onSurfaceVariant,
                ),
              ),
            Icon(icon, size: AppSpacing.xl, color: app.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title.isEmpty ? category : s.title,
                    style: text.titleMedium,
                  ),
                  if (s.displaySegments.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      s.displaySegments.map((seg) => seg.text).join(' '),
                      style: text.bodySmall?.copyWith(color: app.secondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              category,
              style: text.labelSmall?.copyWith(color: app.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 把 [from] 处的环节移到 [to] 处（[to] 为落点索引，插到该元素之前；[to]==length 表示排到最末）。
///
/// 抽成顶层纯函数便于单测：不依赖 widget 状态。
List<CoursewareSectionModel> reorderCoursewareSections(
  List<CoursewareSectionModel> list,
  int from,
  int to,
) {
  final next = List<CoursewareSectionModel>.from(list);
  final item = next.removeAt(from);
  var insertAt = to;
  if (from < to) insertAt = to - 1;
  next.insert(insertAt, item);
  return next;
}
