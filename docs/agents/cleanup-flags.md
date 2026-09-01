# 待清理 / 待删除项 — 娃娃学习 App

> 渐进式披露梳理过程中发现的可疑 / 过期 / 冗余项。本文件供人工复核，不是规范。

## 已处理（本次）

- ✅ **`frontend/.github/copilot-instructions.md`**：旧的「暖绿 / ≥20sp / 低龄友好 / 底部 Tab」设计已过期（被 ADR-0002 / ADR-0003 推翻，且代码已落地 `DesktopShell`、删除 `_MainShell`）。已**重写为指向 `frontend/.impeccable.md` / `CONTEXT.md` / ADR-0003 的指针**，避免 GitHub Copilot 读到冲突设计。
- ✅ **`../architecture/技术架构_后端.md` §5.1**：原「LLMProvider 方法是同步的」描述与代码（`async def` + `await`）冲突。已**修正为「provider 方法均为 async，业务层用 asyncio.run 在线程中调用」**。
- ✅ **`../architecture/技术架构_后端.md` §6**：Task `status(pending|done)` 已过期，已**修正为 `draft→ready→assigned→done`**（ADR-0004 四态，代码实证）。
- ✅ **`flutter/material.dart` 导入迁移（技术债）**：14 个业务文件已从 Material 全量迁移至 `cupertino_ui`（颜色→`CupertinoColors`、路由→`CupertinoPageRoute`、`Scaffold`/`AppBar`→`CupertinoPageScaffold`/`CupertinoNavigationBar`、`IconButton`/`TextButton`→`CupertinoButton`、`Switch`→`CupertinoSwitch`、`RefreshIndicator`→`CupertinoSliverRefreshControl`、`Icons`→`LucideIcons`、`scheme`→`AppTheme.colorsOf`）。`flutter analyze` 通过（No issues found）。唯一残留为 `app_theme.dart` 窄 `import 'package:flutter/material.dart' show ThemeMode;`（详见下）。

## 建议处理（待人工决定）

- ⚠️ **冗余文档**：`../architecture/技术架构_后端.md` 与 `../architecture/项目分析_架构规范与业务功能.md` 高度重叠（同一套架构两套描述）。已在 AGENTS.md 同时建导航并标注「以《技术架构_后端.md》为架构事实源」；若后续仍想二选一可作索引 / 链接，避免将来再次分叉。
- ⚠️ **规划类目录不属于 AGENTS 规范**：
  - `.scratch/wawa-learning/issues/*` —— 议题草稿，应进 issue tracker，不在代理指引范围。
  - `wayfinder/` —— 独立规划 / 票据素材，不是编码约定。

## 过于宽泛 / 显而易见（不应写进任何 AGENTS 文件）

- 「写干净的代码」「保持可读性」「代码要可维护」等无操作性的口号。
- 已被 ADR-0003 推翻的「低龄友好 / 护眼大字」承诺（不要在新规范里残存）。
- 与通用 Flutter / Python 知识重复的基础约定（如「变量命名要有意义」）——代理已默认掌握，无需占用上下文。
