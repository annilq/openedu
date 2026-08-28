# MEMORY.md — 长期记忆

## 项目位置
- 娃娃学习App 项目根目录：`/Users/yunqi/Documents/develop/openedu`
- 曾位于 `/Users/yunqi/WorkBuddy/2026-08-20-11-55-24`，2026-08-20 按用户要求整体迁移至 openedu（原目录仅剩空占位）。

## 技术栈与验证命令
- 后端：FastAPI + SQLModel + SQLite/Postgres，依赖用 `uv`（`cd backend && uv sync`、`uv run pytest`）。无 Alembic，迁移在 `app/core/db.py:run_migrations` 手写 ALTER TABLE，需同时兼容 sqlite `TEXT` 与 postgres `JSON` 并做列存在性检查保证幂等。
- 前端：Flutter + Riverpod + shadcn_ui + cupertino_ui（`cd frontend && flutter analyze`、`flutter test`）。
- LLM 抽象在 `app/domain/provider.py`（`LLMProvider.generate_question`），实现有 `MockProvider`（打标式假数据）与 `LangChainProvider`；业务只依赖接口。

## Flutter / shadcn_ui 约定（踩坑沉淀）
- `LucideIcons` **不是**来自 `lucide_flutter`，而是由 `package:shadcn_ui/shadcn_ui.dart` 再导出；任何用到 `LucideIcons` 的 dart 文件必须 import `shadcn_ui`（`app_theme.dart` 正是因已 import 它才可用）。
- 表单输入统一用 `AppTextField`（非 Flutter `TextField`）：其 label 是 `ShadInput` 的**兄弟** `Text`，输入框为 shadcn `ShadInput`（内部 `EditableText`）。
  - 测试里 `find.widgetWithText(TextField, label)` 恒匹配 0；应改用「包含该 label 的 `AppTextField`」作为 `tester.enterText` 目标（`showKeyboard` 在其后代中找 `EditableText`，`matchRoot: true`）。
- 含 shadcn 组件（如 `ShadButton`）的 widget 测试需要 `ShadTheme` 祖先；`ShadApp` 基于 `WidgetsApp` 而非 `MaterialApp`，故用 `ShadApp.custom(appBuilder: (ctx) => MaterialApp(home: X))` 可同时满足 ShadTheme 与 Material。生产入口 `lib/main/app.dart` 同样是 `ShadApp.custom`（内层 CupertinoApp + ShadAppBuilder）。
- 长表单页的提交按钮常落在默认测试视口（800×600）外，点击前需滚动；树中存在多个 `Scrollable` 时，`scrollUntilVisible` 必须显式传 `scrollable: find.byType(Scrollable).first`，否则抛 "Bad state: Too many elements"。
- `flutter analyze` 应清零 unused_element / unused_import：改建页面后常残留旧回调或重复 import（如 provider 已定义在 `children_provider.dart` 就不必再 import `children_notifier.dart`）。
