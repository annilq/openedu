import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../shared/domain/models/models.dart';
import '../../../../../shared/theme/app_theme.dart';
import '../../../../../shared/widgets/app_loading.dart';
import '../../../../../shared/widgets/app_sidebar.dart';
import '../../../../children/providers/children_provider.dart';
import '../../../../children/presentation/providers/children_notifier.dart';
import '../../providers/selected_child_provider.dart';

/// 侧栏顶部娃娃选择器：显示当前选中娃娃，点击弹出列表切换。
/// 娃娃列表加载完成时自动选中第一个。
///
/// **不自带任何外边距**——四向内边距由宿主 [AppSidebar] 统一给
/// （[AppLayout.sidebarHeaderPadding]）。自带的 `Padding(right:)` 会让同一侧栏内
/// 出现「头部贴边 / 导航缩进」的双左缘，且渲染在抽屉里时那条右内边距没有对应物。
///
/// 展开态渲染「卡片 + 右侧收缩按钮」同行；轨态（[SidebarCollapseScope] 收缩）只渲染
/// 头像——宽度容不下姓名，但「当前在看谁」不能丢，与底部 [AdaptiveUserBlock] 的降级
/// 方式一致。
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

  @override
  void dispose() {
    _popoverCtrl.dispose();
    super.dispose();
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

    // 锚点分两档（抽屉无 scope → 视为展开，与触发卡的降级判据同一处口径）。
    //
    // 【展开 / 抽屉】浮层左上对齐触发卡左下 + [AppSpacing.xs] 间隙 → 开在触发卡
    // **下方、左缘齐平**，整体落在侧栏内（正是 [ShadAnchor] 的默认对齐，只补了间隙）。
    //
    // 【轨态】浮层左上对齐触发卡**右上** → 向轨的右侧飞出、顶端齐平。
    // 轨态若沿用「下方、左缘齐平」，浮层（宽 224）会盖住整条 64px 轨道，
    // 把导航图标挡掉——而轨态的存在意义就是「收起后信息不能丢」（ADR-0046）。
    // 飞出不覆盖轨道，是图标轨道的通用做法。
    //
    // 必须显式给 anchor，不能用 shadcn 默认的 `ShadAnchorAuto`：
    // 它的默认是 `bottomCenter ↔ bottomCenter` = **相对触发卡水平居中**，而底层的
    // `positionDependentBox` 还会再居中一次。触发卡只有 171 宽、浮层 224 宽，
    // 居中即两侧各溢出约 26px，且左溢部分被屏幕左缘钳住——实测浮层外框左缘落在
    // 窗口 x=0（比触发卡左缘还靠左 8px）、右缘 244，比侧栏（240）还宽 5px。
    //
    // 命名方向容易读反，按实现接线记：[ShadAnchor.childAlignment] 作用在**浮层**上、
    // [ShadAnchor.overlayAlignment] 作用在**触发卡**上（见 shadcn `raw_components/portal.dart`
    // 的 `followerAnchor: anchor.childAlignment`）。
    final collapsed =
        SidebarCollapseScope.maybeOf(context)?.collapsed ?? false;
    final anchor = collapsed
        ? const ShadAnchor(overlayAlignment: Alignment.topRight)
        : const ShadAnchor(offset: Offset(0, AppSpacing.xs));

    return ShadPopover(
      controller: _popoverCtrl,
      anchor: anchor,
      child: _buildTrigger(scheme, childrenState, selected),
      popover: (_) => _buildPopover(scheme, childrenState, selected),
    );
  }

  Widget _buildTrigger(
      AppColors scheme, ChildrenState state, SelectedChild? selected) {
    final text = AppTheme.textOf(context);
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

    // 轨态：宽度只剩 48，放不下姓名。只留头像（无娃娃时留「+」）。
    //
    // 刻意**不用** [AppCard] 包一层描边——轨态里导航图标与收缩按钮都是无描边的
    // 悬停药丸，唯独头像套个框会显得是另一类东西；与 [AdaptiveUserBlock] 在轨态
    // 去掉文字、只留头像的降级方式一致。
    final collapsed =
        SidebarCollapseScope.maybeOf(context)?.collapsed ?? false;
    if (collapsed) {
      return AppFocusableAction(
        onTap: () => _popoverCtrl.toggle(),
        semanticLabel: hasChildren ? '切换娃娃：$name' : '添加娃娃',
        borderRadius: BorderRadius.circular(AppRadius.chip),
        hoverHighlight: true,
        child: SizedBox(
          width: AppLayout.tapTarget,
          height: AppLayout.tapTarget,
          child: Center(
            child: hasChildren
                ? AvatarSquircle.xs(name: name)
                : Icon(LucideIcons.plusCircle, size: 18, color: scheme.accent),
          ),
        ),
      );
    }

    return SizedBox(
      // 与右侧收缩按钮同高，二者基线齐平（[AppLayout.tapTarget]）。
      height: AppLayout.tapTarget,
      child: AppCard.listRow(
        onTap: () => _popoverCtrl.toggle(),
        // 外边距归零：头部内边距由 AppSidebar 统一给，这里再留 margin 会双份。
        margin: EdgeInsets.zero,
        // 仅横向内边距：高度由外层 SizedBox 钉死，纵向 padding 会把内容挤扁。
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            if (hasChildren)
              AvatarSquircle.xs(name: name)
            else
              Icon(LucideIcons.plusCircle, size: 20, color: scheme.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: hasChildren ? name : '添加娃娃',
                      style: text.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        // 无娃娃时这个触发器的语义从「当前是 A」变成「去添加」，
                        // 用 accent 表态是动作，而不是把动作名当成娃娃名。
                        color: hasChildren ? scheme.onSurface : scheme.accent,
                      ),
                    ),
                    if (hasChildren && grade > 0)
                      TextSpan(
                        text: ' · $grade年级',
                        style: text.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(LucideIcons.chevronsUpDown,
                size: 14, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildPopover(
      AppColors scheme, ChildrenState state, SelectedChild? selected) {
    final children = state is ChildrenLoaded ? state.children : const [];

    // 加载中与空列表都只出底部「添加娃娃」——空态下这才是唯一有意义的动作。
    return Container(
      // 宽度令牌指的是**外框**宽（= 侧栏内容列），而本 Container 是浮层内容、
      // 外面还裹着主题的内边距与 2px 描边，所以内容侧要减去 [AppLayout.popoverChrome]。
      // 直接写 224 会让外框变成 244 —— 比侧栏还宽，就是这次要修的溢出。
      width: AppLayout.sidebarMenuWidth - AppLayout.popoverChrome,
      constraints: const BoxConstraints(maxHeight: AppLayout.menuMaxHeight),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (children.isNotEmpty)
            Flexible(
              // 娃娃多时内部滚动，而不是把浮层顶破（原先 Column 直接溢出）。
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final c in children)
                    _ChildOption(
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
                    ),
                ],
              ),
            ),
          if (children.isNotEmpty)
            Padding(
              // 结构分隔线**通栏**（不留横向缩进）：它是面板级结构边，与侧栏右缘、
              // 顶栏底边同档。原先缩进 `md`(12) 而选项缩进 4、CTA 缩进 8，
              // 同一面板里出现三条左边缘——那才是「看着不规范」的来源。
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Container(
                height: AppElevation.borderWidthHairline,
                color: scheme.outline,
              ),
            ),
          Padding(
            // 横向缩进与 [_ChildOption] 的选项药丸一致（`xs`）——CTA 与选项同为
            // 面板里的「项」，左缘必须同一条。
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.xs),
            child: AppPrimaryButton(
              label: '添加娃娃',
              icon: LucideIcons.plus,
              onPressed: _openAddChild,
            ),
          ),
        ],
      ),
    );
  }
}

/// 浮层里的单个娃娃选项。
///
/// 刻意**不用** [AppCard.listRow]：那会在一个已带描边的浮层里再套一层带描边的盒子
/// （盒中盒），把「选中」和「容器边界」两件事混成同一种视觉。改用与侧栏导航项
/// （[AppSidebarItem]）同一套选中语言——无描边药丸，选中给 `surfaceActive` 底色 +
/// accent 图标。全站「在列表里表示选中」只有这一种语言。
class _ChildOption extends StatelessWidget {
  final String name;
  final int? grade;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final AppColors scheme;

  const _ChildOption({
    required this.name,
    this.grade,
    required this.active,
    required this.onTap,
    this.onEdit,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final text = AppTheme.textOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: AppFocusableAction(
        onTap: onTap,
        semanticLabel: name,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        hoverHighlight: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: active ? scheme.surfaceActive : CupertinoColors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Row(
            children: [
              AvatarSquircle.xs(name: name),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (grade != null && grade! > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: Text('$grade年级',
                            style: text.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
              if (onEdit != null) _ChildEditAction(onTap: onEdit!),
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

/// 行内「编辑娃娃资料」小按钮。
///
/// 方形命中区走 [AppControl.heightSmOf]（与输入框里的眼睛按钮同档，见 `app_inputs.dart`），
/// 并接 [AppFocusableAction] 进焦点树——原先是一个裸 `GestureDetector` 套 16px 图标，
/// 命中区只有 16px 且键盘永远 Tab 不到。
class _ChildEditAction extends StatelessWidget {
  final VoidCallback onTap;
  const _ChildEditAction({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.colorsOf(context);
    final side = AppControl.heightSmOf(context);
    return AppFocusableAction(
      onTap: onTap,
      semanticLabel: '编辑娃娃资料',
      borderRadius: BorderRadius.circular(AppRadius.chip),
      hoverHighlight: true,
      child: SizedBox(
        width: side,
        height: side,
        child: Icon(LucideIcons.pencil,
            size: 14, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
