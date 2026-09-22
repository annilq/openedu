# Copilot Instructions — 娃娃学习 (openedu Flutter)

> 本文件只做指针，不在此维护重复的设计描述。设计规范以以下事实源为准：

- 设计系统（令牌 / 字号 / 描边 / 动效 / 配色 / 空态）：仓库根 [`../../.impeccable.md`](../../.impeccable.md)
- 设计语言决策与当前视觉方向：ADR-0044（新粗野 Neo-Brutalism，高饱和撞色 + 2px 墨黑描边 + 无模糊硬阴影 + 弹性动效）
- 领域术语与错误码：[`../../CONTEXT.md`](../../CONTEXT.md)
- 单文件行数 / 组件编写门禁：ADR-0058（`../../docs/adr/0058-frontend-file-size-and-component-authoring.md`）
- 架构与分层硬规则：[`../../docs/agents/frontend.md`](../../docs/agents/frontend.md)、[`../../docs/agents/architecture.md`](../../docs/agents/architecture.md)
- AI 代理总指引（命令 / 包管理器 / 分层）：仓库根 [`../../AGENTS.md`](../../AGENTS.md) 与 `docs/agents/`

## 当前生效的设计方向（ADR-0044 新粗野）

- 平板优先，家长端 / 娃娃端双模式（`AppUserMode`）。
- 高饱和原色撞色 + 2px 墨黑（`#111110`）描边 + 无模糊硬阴影（常态 `Offset(3,3)`，按压 `Offset(1,1)`）+ 弹性（spring）动效。
- 层级由描边与位移承担，不依赖色块面积；强调色块单卡片填充 ≤ 40%、单屏色相 ≤ 3。
- 全站颜色 / 间距 / 字号 / 转场时长只走设计令牌（`AppColors` / `AppSpacing` / `AppText._typeScale`），组件禁止硬编码 `Colors.*` 与魔法十六进制。
- 学科标识三重编码：色相 + 明度差 + 几何标记（数学 ■ / 语文 ● / 英语 ▲），禁止仅靠颜色。

> 旧版「护眼暖色 / ≥20sp / 低龄友好 / 底部 Tab」与「中性靛蓝 / 15sp / 无阴影」描述均已废弃，请勿参考。
