import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../children/domain/providers/children_provider.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../providers/selected_child_provider.dart';

/// 侧栏顶部娃娃选择器：显示当前选中娃娃，点击弹出列表切换。
/// 娃娃列表加载完成时自动选中第一个。
class ParentChildSelector extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToAddChild;
  final void Function(UserModel child)? onNavigateToEditChild;

  const ParentChildSelector({
    super.key,
    this.onNavigateToAddChild,
    this.onNavigateToEditChild,
  });

  @override
  ConsumerState<ParentChildSelector> createState() =>
      _ParentChildSelectorState();
}

class _ParentChildSelectorState extends ConsumerState<ParentChildSelector> {
  final _popoverCtrl = ShadPopoverController();
  bool _triggerHovered = false;

  @override
  void dispose() {
    _popoverCtrl.dispose();
    super.dispose();
  }

  void _setHover(bool v) {
    if (_triggerHovered != v) setState(() => _triggerHovered = v);
  }

  Future<void> _openAddChild() async {
    _popoverCtrl.hide();
    if (widget.onNavigateToAddChild != null) {
      widget.onNavigateToAddChild!();
      return;
    }
    // Fallback: push (standalone usage)
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final childrenState = ref.watch(childrenNotifierProvider);
    final selected = ref.watch(selectedChildProvider);

    ref.listen<ChildrenState>(childrenNotifierProvider, (prev, next) {
      if (next is ChildrenLoaded &&
          next.children.isNotEmpty &&
          selected == null) {
        ref
            .read(selectedChildProvider.notifier)
            .select(next.children.first.id, next.children.first.grade ?? 2);
      }
    });

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: ShadPopover(
        controller: _popoverCtrl,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _popoverCtrl.toggle(),
          child: _buildTrigger(scheme, childrenState, selected),
        ),
        popover: (_) => _buildPopover(scheme, childrenState, selected),
      ),
    );
  }

  Widget _buildTrigger(
      AppColors scheme, ChildrenState state, SelectedChild? selected) {
    String name = '选择娃娃';
    int grade = 0;
    bool hasChildren = false;

    if (state is ChildrenLoaded && state.children.isNotEmpty) {
      hasChildren = true;
      if (selected != null) {
        for (final c in state.children) {
          if (c.id == selected.id) {
            name = c.displayName;
            grade = c.grade ?? 0;
          }
        }
      } else {
        name = state.children.first.displayName;
        grade = state.children.first.grade ?? 0;
      }
    }

    if (state is ChildrenLoading || state is ChildrenInitial) {
      return const Padding(
        padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: AppLoading(),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: _triggerHovered
              ? scheme.surfaceHover
              : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Row(
          children: [
            if (hasChildren)
              AvatarSquircle.xs(name: name)
            else
              Icon(LucideIcons.plusCircle, size: 20, color: scheme.accent),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: hasChildren ? name : '添加娃娃',
                      style: AppTheme.textOf(context).labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                    ),
                    if (hasChildren && grade > 0)
                      TextSpan(
                        text: ' · $grade年级',
                        style: AppTheme.textOf(context).labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasChildren)
              Icon(LucideIcons.chevronsUpDown,
                  size: 14, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildPopover(
      AppColors scheme, ChildrenState state, SelectedChild? selected) {
    if (state is! ChildrenLoaded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text('加载中...', style: AppTheme.textOf(context).bodyMedium),
      );
    }
    if (state.children.isEmpty) {
      return _ChildOption(
        name: '添加娃娃',
        icon: LucideIcons.plusCircle,
        active: false,
        onTap: _openAddChild,
        scheme: scheme,
      );
    }
    return Container(
      width: 224,
      constraints: const BoxConstraints(maxHeight: 400),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...state.children.map((c) => _ChildOption(
                name: c.displayName,
                grade: c.grade ?? 0,
                active: selected?.id == c.id,
                onTap: () {
                  ref
                      .read(selectedChildProvider.notifier)
                      .select(c.id, c.grade ?? 2);
                  _popoverCtrl.hide();
                },
                onEdit: widget.onNavigateToEditChild == null
                    ? null
                    : () {
                        _popoverCtrl.hide();
                        widget.onNavigateToEditChild!(c);
                      },
                scheme: scheme,
              )),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
            child: Container(height: 1, color: scheme.outline),
          ),
          _ChildOption(
            name: '添加娃娃',
            icon: LucideIcons.plusCircle,
            active: false,
            onTap: _openAddChild,
            scheme: scheme,
          ),
        ],
      ),
    );
  }
}

class _ChildOption extends StatelessWidget {
  final String name;
  final int? grade;
  final bool active;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final AppColors scheme;

  const _ChildOption({
    required this.name,
    this.grade,
    required this.active,
    this.icon,
    required this.onTap,
    this.onEdit,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            color: active ? scheme.surfaceActive : CupertinoColors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Row(
            children: [
              if (icon != null)
                Icon(icon,
                    size: 18,
                    color: active ? scheme.accent : scheme.onSurfaceVariant)
              else
                AvatarSquircle.xs(name: name),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.textOf(context)
                              .labelMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              )),
                    ),
                    if (grade != null && grade! > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: Text('$grade年级',
                            style: AppTheme.textOf(context)
                                .labelSmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                )),
                      ),
                  ],
                ),
              ),
              if (onEdit != null)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onEdit,
                      child: Icon(LucideIcons.pencil,
                          size: 16, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              if (active)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Icon(LucideIcons.check,
                      size: 16, color: scheme.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
