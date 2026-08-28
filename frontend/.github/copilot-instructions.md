# Copilot Instructions — 娃娃学习 (kids_learn)

> **本文件已改为指针。** 项目的设计规范以以下事实源为准，请勿在此维护重复的设计描述：
>
> - 设计系统（令牌 / 字号 / 动效 / 配色）：[`../.impeccable.md`](../.impeccable.md)
> - 设计系统术语与错误码：[`../CONTEXT.md`](../CONTEXT.md)
> - 单文件行数门禁：[`../CODE_CONVENTIONS.md`](../CODE_CONVENTIONS.md)
> - 架构决策（ADR-0002 中性灰白 + 桌面壳、ADR-0003 Linear 化重设计）：[`../docs/adr/0002-neutral-default-theme-and-desktop-shell.md`](../docs/adr/0002-neutral-default-theme-and-desktop-shell.md) 与 [`../docs/adr/0003-linear-refinement-delete-warmgreen-dense-type.md`](../docs/adr/0003-linear-refinement-delete-warmgreen-dense-type.md)
> - AI 代理总指引（命令 / 包管理器 / 分层）：仓库根 [`../../../AGENTS.md`](../../../AGENTS.md) 与 [`../../../docs/agents/`](../../../docs/agents/)

## 速览（当前生效的设计方向，ADR-0003）

- 主要用户是**家长**（专业工作台），家长专业体验 > 低龄友好。
- **中性 + 靛蓝**设计语言：微暖白 surface、纯白卡片、1px 描边分层、**无阴影**；单一靛蓝强调色 `#5E6AD2`（暗 `#7B82EA`）；CTA 近黑底白字。
- **密排 15sp** 统一字号（Inter 西文 / 数字 + HarmonyOS Sans SC CJK 回退）。
- 桌面左右分栏壳（`DesktopShell` + `AppSidebar`），底部 Tab 已移除。
- 所有间距 / 圆角 / 字号走令牌（`AppSpacing` / `AppRadius` / `AppText`），禁止 `Colors.*` 硬编码；UI 组件统一用 `app_theme.dart` 的 `App*` 语义组件；表现层基于 `cupertino_ui`。

> 旧版「暖绿 `#43A047` / ≥20sp / 低龄友好 / 底部 Tab」描述已废弃，请勿参考。
