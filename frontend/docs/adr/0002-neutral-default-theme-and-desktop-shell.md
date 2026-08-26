# ADR-0002: 采用中性灰白默认主题 + 桌面左右分栏壳

- **Status**: Accepted
- **Date**: 2026-08-25
- **Supersedes**: teach-impeccable 确认的「暖绿为默认主题」约定（仅配色默认值层面反转，暖绿身份保留为备选）

## Context

当前 App 默认使用 teach-impeccable 确认的暖绿护眼主题（主色 `#43A047`、暖白 `#FDF8F0`、暖调深炭暗色），顶层导航为 `_MainShell` 的底部双 Tab（首页 / 我的），其余功能页（做题 / 错题 / AI 伴学 / 娃娃管理 / AI 管控）从 `home_screen` 内部 push 进入，埋在 2-3 层深。

用户希望参考 Claude / Codex desktop：默认观感改为灰+白，操作区改为左侧菜单栏 + 右侧内容栏的桌面分栏形态。

## Decision

1. **默认主题改为中性灰白**：表面纯中性（无绿色强调），选中/CTA 用近黑 + 浅灰药丸，忠实于 desktop 工具观感。
2. **暖绿主题保留为可切换备选**：不删除现有暖绿令牌，作为用户可选的第二套配色。
3. **双角色（家长 / 娃娃）均采用左菜单 + 右内容 desktop 壳**，替换现有底部 Tab 壳。屏幕足够大，侧栏后续可收缩，低龄用户负担靠收缩态缓解。
4. **配色与亮暗正交**：配色选择（灰白 / 暖绿）× 外观（亮 / 暗 / 跟随系统），默认 = 灰白 + 跟随系统。
5. **侧栏一级入口扩展**：把当前埋在 `parent_dashboard` / `child_home` 内部的功能页提为侧栏一级项，顺带满足单文件 ≤300 行规范（`parent_dashboard` 1074 行必须拆分）。

## Consequences

- **正面**：导航层级从 2-3 层降到 1 层；默认观感更「工作台」、信息密度更高；暖绿身份不丢；`parent_dashboard` 拆分有明确切面（按侧栏项）。
- **负面**：推翻「暖绿为默认」的既定方向（ADR 级反转，本文件即记录该反转）；中性主题需新增一套令牌；娃娃端左菜单对低龄用户有阅读/操作负担，靠「可收缩 + 后续优化」缓解，是一笔已知债务。
- **令牌签名**：`AppTheme.shadThemeData` 需扩展为 `(brightness, colorScheme)`，新增 `colorSchemeProvider`（neutral | warmGreen），与 `themeModeProvider`（system/light/dark）正交。

## Alternatives considered

- **灰白底 + 保留绿色强调**（绿色只用于选中/CTA/进度）：否决。两套主题差异将只剩表面色，用户明确选「纯中性不放绿」（A）。
- **仅家长端 desktop 壳、娃娃端保卡片**：否决。用户要求双角色都改，理由是屏幕够大、侧栏可收缩。
- **大爆炸式一次性 repave**：否决。采用分阶段（令牌 → 家长壳 → 娃娃壳 → 收缩态），每阶段保持 `dart analyze` 零回归。

## Mapping（侧栏一级项 → 现有屏幕）

**家长侧栏**：概览(parent_dashboard 概览段) / 娃娃管理(add_child_screen) / 错题本(wrong_questions_screen) / AI 管控(tutor_quota_screen) / 我的(profile_screen)

**娃娃侧栏**：首页(child_home) / 做题(practice_screen) / 错题本(wrong_questions_screen) / AI 伴学(tutor_chat_screen) / 我的(profile_screen)

## Phase Progress

- **Phase 1（令牌 + 切换）** ✅ `dart analyze` 零回归。`AppColorScheme { neutral, warmGreen }` + `colorSchemeProvider`（持久化，默认 neutral），与 `themeModeProvider` 正交。`AppTheme.neutralLight/neutralDark` 新增。
- **Phase 2（家长 desktop 壳 + dashboard 拆分）** ✅ `dart analyze` 零回归。新增 `DesktopShell` + `AppSidebar`/`AppSidebarItem`/`AppSidebarDivider`。`parent_dashboard.dart`（1074 行）拆分为 5 个右栏视图 + 侧栏 + 子选择器。
- **Phase 3（娃娃 desktop 壳 + 删底部 Tab）** ✅ `dart analyze` 零回归。新增 `ChildSidebar`，`home_screen` 娃娃分支切 `DesktopShell` + `IndexedStack`，`app.dart` 删除 `_MainShell`/`_NavItem`/`_NavItemButton` 死代码（280→148 行）。3 个子屏幕加 `showBack` 参数。
- **Phase 4（侧栏收缩态 + active 左竖条 + 动画）** ✅ `dart analyze` 零回归。
  - `DesktopShell` 改 `ConsumerStatefulWidget`，宽度 `AnimatedContainer`（280ms easeOutCubic），收缩态持久化到 `SharedPreferences`（`sidebar_collapsed` key）。
  - 新增 `SidebarCollapseScope` InheritedWidget 向侧栏子树广播收缩态 + toggle 回调。
  - `AppSidebarItem` 收缩态只显示居中图标（隐藏 label/trailing/左竖条），active 用药丸背景区分。
  - `AppSidebar` 顶部增加 `_CollapseToggle`（panelLeftOpen/Close 图标），收缩态隐藏 `top` 区。
  - `AppSidebarDivider` 收缩态退化为纯间距。
  - 家长/娃娃 `_SidebarBottom` 收缩态只显示头像（tap 触发 logout）。
