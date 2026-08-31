# 双模式落地（Step ②，ADR-0014）

> 配套 Step ①（规范一致性审计）。本步把 ADR-0014 的「双模式 / 学科色 / AppUserMode 切换」真正落到主题层与运行时，使双模式可被家长在设置里切换并全局生效。
> `flutter analyze` 验证：**No issues found**。

## 改动清单

### 1. `frontend/lib/shared/theme/app_theme.dart`（核心主题层）
- **`AppUserMode` 枚举**（`parent` / `child`）：独立于亮暗主题，控制字号阶梯与语气。
- **`SubjectKey` / `SubjectColors` / `SubjectAccent`**：学科色令牌（数学蓝 / 语文玫瑰 / 英语翠绿 + `reserved` 预留槽），亮暗各一套，提供 `resolve` / `forContext` / `label` / `fromName`。与 `.impeccable.md` §Subject Accent Tokens 数值完全一致。
- **Child Mode 字号阶梯**：`AppText._build` 新增 `child` 参数，整套令牌放大一档（displayLarge 22→26、bodyLarge 15→17…），并放宽正文行高（1.5→1.55）。`AppTheme` 预建 4 个 `AppText` 实例（light/dark × parent/child）。
- **`AppTheme.textOf(context, {mode})`**：默认从 `UserModeScope` 读取模式，全局 `Text(style: textOf...)` 随模式切换自动重建（无需逐个 widget 监听 provider）；支持显式 `mode` 覆盖。
- **Shad 文本主题同步**：`shadFor(isDark, [mode])` 与 `_shadTextTheme(c, child:)` 支持 Child 放大映射（向后兼容，旧调用仍可用）。
- **`UserModeScope`（InheritedWidget）**：把当前 `AppUserMode` 注入 Widget 树；未挂载时默认 `parent`，避免崩溃。
- **`AppTags.subject(SubjectKey)`**：学科色 chip 助手（container 底 + fg 字），仅供小面积学科标识使用，落实学科色消费入口。

### 2. `frontend/lib/shared/data/local/storage_service.dart`
- 新增 `user_mode` 持久化键 + `getUserMode()` / `saveUserMode()`，复用 `AppUserMode` 枚举（默认 `parent`）。

### 3. `frontend/lib/shared/theme/theme_provider.dart`
- 新增 `userModeProvider`（`StateNotifierProvider<AppModeController, AppUserMode>`），完全沿用 `themeModeProvider` 模式（初始化读存储、写入即持久化）。

### 4. `frontend/lib/main/app.dart`（真正生效的接线）
- `build` 监听 `userModeProvider`，重建 `shadFor(isDark, userMode)`（theme + darkTheme 均带模式）。
- `builder` 用 `UserModeScope(mode: userMode)` 包裹整个导航子树 → 所有 `textOf(context)` 自动随模式重建。

### 5. `frontend/lib/features/profile/presentation/screens/profile_screen.dart`
- 「外观」区新增 **家长模式 / 娃娃模式** 切换段（复用 `_ThemeModeSetting` 的 segmented 控件样式），切换即持久化并即时全局生效。

## 设计要点
- **双模式靠令牌分化，不建两套体系**：surface / spacing / radius 全共享，仅字号阶梯 + 学科色权重分化（与 ADR-0014 原则一致）。
- **全局自动重建**：用 `InheritedWidget` 而非逐个 widget 监听 provider，把"双模式生效"的成本压到最低，新增页面天然继承。
- **学科色约束**：仅用于学科标识 / 进度条 / 图标容器 / 小面积 chip；本步只落地令牌 + `AppTags.subject` 入口，实际消费（娃娃端学科徽章、掌握度可视化）留待 Step ③ 响应式壳与娃娃端页面。

## 验证
- `flutter analyze`：No issues found（修复了 `unnecessary_import` 与 `use_key_in_widget_constructors` 两个 lint）。
- 真机/模拟器 `flutter run` 后，进入「我的 → 外观 → 娃娃模式」，全站字号应即时放大、学科色可用。

## 下一步（未做）
- **③ `DesktopShell` → `AdaptiveShell`**：按断点（compact <700 / medium 700–1023 / expanded ≥1024）切换底部导航 / 抽屉 / 侧栏，并接入学科色到娃娃端页面与掌握度可视化。
