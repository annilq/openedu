# 双模式设计令牌与自适应壳（设计令牌层）

前端双模式在「设计系统与自适应壳」层面的具体约定（学科 accent 令牌、Child Mode 字号阶梯/放大一档、转场时长令牌、adaptive_shell 断点）。与 ADR-0002 互补：0002 是双模式业务架构层（原 ADR-0014 编号），本 ADR 是设计令牌层，不矛盾。

- **响应式导航壳断点**：`AdaptiveShell` 按 `LayoutBuilder` 宽度在三档断点切换（≥700 侧栏 240↔64 可收起；<700 娃娃端底部导航 / 家长端顶部汉堡+抽屉）（`frontend/lib/shared/widgets/adaptive_shell.dart:28`、`:43-45`）。
- **用户模式双模式**：`AppUserMode`（家长工作台 / 娃娃学习台）独立于亮暗主题，控制字号阶梯与语气（`frontend/lib/shared/theme/app_theme.dart:25`、`:29`）；持久化于 `StorageService`（`frontend/lib/shared/data/local/storage_service.dart:38`）。
- **学科 Accent 令牌**：`SubjectKey` + `SubjectAccent` 解析数学/语文/英语的 accent/container/fg 三件套（仅小面积业务标识色），注入 shadcn custom 档（`frontend/lib/shared/theme/app_theme.dart:31`、`:344`）。
- **Child Mode 整体放大一档**：`AppText` 与 `AppTheme._shadTextTheme` 共用 `_typeScale` 单一事实源，Child Mode 经 `_childScale` 整体放大一档（`frontend/lib/shared/theme/app_theme.dart:692`、`:869-880`）。
- **转场时长令牌**：`AppMotion` 三档（交互 120 / 状态 200 / 页面 300ms）+ Child Mode 庆祝档 450ms（`frontend/lib/shared/theme/app_theme.dart:1637`、`:1638`）。
- **学科色是业务标识色**：`theme_preview` 校验学科色仅作业务标识，与四档语义色区分（`frontend/lib/dev/theme_preview.dart:857`）。

**Considered Options**：① 双模式各写一套主题/排版表（漂移、拒绝）；② 单一事实源令牌 + `UserModeScope` 作用域切换（采用）。

**Consequences**：所有组件经 `UserModeScope` 自动重建，模式切换零侵入；新增页面须声明对双模式的适配，否则在 `theme_preview` 自检暴露脱节。
