# Parent/Child 双模式设计

同一应用内以「用户模式」切换家长工作台与娃娃学习台，而非两个独立 App（原 ADR-0014）。

- **模式切换**：`AppUserMode`（家长 / 娃娃）持久化（`frontend/.../storage_service.dart:38`），在根 `AdaptiveShell` 作用域生效（`frontend/.../adaptive_shell.dart:28`）。
- **学科色（Subject Accent Tokens）**：作为业务标识色注入主题 custom 档，与家长语义色（含 AI 归 info 共四档）区分（`frontend/.../app_theme.dart:344`、theme_preview 校验）。
- **双模式字号阶梯**：Child Mode 在 Parent 基础上整体放大一档，排版取自 `AppText._typeScale` 单一事实源，消除双排版表漂移（`frontend/.../app_theme.dart:692`、`:1637`）。
- **响应式壳**：`AdaptiveShell` 按 `LayoutBuilder` 宽度在三档断点切换导航布局（tablet-first）。

**Consequences**：任何新页面必须声明对双模式的适配（文案第一人称切换、字号档、学科色消费），否则在 `theme_preview` 自检中暴露主题层与令牌脱节。
