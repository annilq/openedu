import 'package:flutter/widgets.dart';

import 'app_sidebar.dart';

/// 导航目的地（数据驱动）：同一份定义同时喂给侧栏 / 底栏 / 抽屉三种形态，
/// 避免三种布局各写一套 item，保证选中态与回调唯一来源。
///
/// 从 [AdaptiveShell] 抽到本文件（ticket 07）：分组结构 [SidebarSection] 也需要它，
/// 而把它留在壳里会让壳越过文件规模基线（ADR-0058 棘轮）。本文件只依赖
/// [app_sidebar]，不反向依赖壳，故不形成循环依赖。
class AdaptiveNavDestination {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final Widget? trailing;

  const AdaptiveNavDestination({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
    this.trailing,
  });
}

/// 侧栏分组：可选标题 + 一组目的地（ticket 07）。
///
/// 标题只在展开态显示（[AppSidebarGroupTitle]），收起态（仅图标）退化为间距；
/// 抽屉（全宽面板，无收缩 scope）始终显示标题。把「教学 / 备课资源 / 系统」这类
/// 分组从渲染细节提升为数据，侧栏与抽屉共用同一份分组——改名与重排只改这一处。
class SidebarSection {
  final String? title;
  final List<AdaptiveNavDestination> items;

  const SidebarSection({this.title, required this.items});
}

/// 把分组结构展开成侧栏 / 抽屉共用的 widget 列表：可选组标题 + 各项。
///
/// [itemBuilder] 由调用方注入，因为侧栏用 [AppSidebarItem]、抽屉用壳私有的
/// `_DrawerItem`——两者都是「图标 + 文字 + 选中」同一套语言，但焦点环与关闭动作不同。
List<Widget> buildNavSectionWidgets(
  List<SidebarSection> sections, {
  required Widget Function(AdaptiveNavDestination destination) itemBuilder,
}) =>
    [
      for (final section in sections)
        ...<Widget>[
          if (section.title != null)
            AppSidebarGroupTitle(title: section.title!),
          ...section.items.map(itemBuilder),
        ],
    ];

/// 把分组拍平成目的地列表：底栏等不需要组标题的消费方用。
List<AdaptiveNavDestination> flattenNavSections(List<SidebarSection> sections) =>
    [for (final section in sections) ...section.items];
