# 05: 迁移遗留 M3 视觉令牌（实际 42 文件）

**What to build:** 仍在使用旧 M3 兼容令牌名（`infoContainer`/`primaryContainer`/`surfaceContainer` 等）的文件，全部改用 ADR-0044 新令牌名；旧名在消费者侧零引用。宽重构：新名已存在，本票只做迁移批次。

**Blocked by:** None

**Status:** done（commit `7e938e4`）

- [x] 全仓 grep 旧令牌名集合命中数（消费者侧，排除 app_theme.dart）归零。
- [x] `flutter analyze` 通过（No issues found!）。
- [x] `flutter test` 全量 552/552 passed。
- [ ] 42 个文件的视觉效果经 `dev/theme_preview.dart` 目视无缺色/无报错（纯词法重命名、色值零变化，待人工目视确认；非自动化回归）。

## 实施记录（2026-10-13）

### 实测范围修正
原 spec 写「23 文件」+ grep 正则 `infoContainer|primaryContainer|onPrimaryContainer|secondaryContainer|onSecondaryContainer|tertiaryContainer|onTertiaryContainer|errorContainer|onErrorContainer|surfaceContainerLowest|surfaceContainerHigh|surfaceContainerHighest` —— 该正则**漏了** `onInfoContainer`、裸 `surfaceContainer`、`surfaceContainerLow`，故少算。实际消费者命中 **42 个 lib 文件**（脚本 `rg` 全量扫描 `frontend/lib` 排除 `app_theme.dart` 得到）。测试目录 `frontend/test` 零命中（无需动）。

### 令牌映射（全部色值零变化）
旧名为 M3 角色名；新名是 `AppColors` 早已存在的语义/表面 getter（app_theme.dart:1092-1125）。每一对底层 hex **逐字节相同**，故本迁移是纯词法替换、视觉无任何变化：

| 旧（M3） | 新（ADR-0044） | 同值证据 |
|---|---|---|
| `infoContainer` | `semanticInfo` | app_theme.dart:328 / :1123 |
| `onInfoContainer` | `semanticInfoFg` | :329 / :1125 |
| `primaryContainer` | `semanticInfo` | **:293 == :328**（均 0xFFDCE7FA 亮 / 0xFF16233D 暗） |
| `onPrimaryContainer` | `semanticInfoFg` | **:294 == :329**（均 0xFF1D4E9C / 0xFFB3C9F7） |
| `secondaryContainer` | `semanticWarning` | :298 / :1113 |
| `onSecondaryContainer` | `semanticWarningFg` | :299 / :1115 |
| `tertiaryContainer` | `semanticPositive` | :303 / :1108 |
| `onTertiaryContainer` | `semanticPositiveFg` | :304 / :1110 |
| `errorContainer` | `semanticError` | :308 / :1118 |
| `onErrorContainer` | `semanticErrorFg` | :309 / :1120 |
| `surfaceContainerLowest` | `surfaceRaised` | :313 == surfaceContainerLow(:314) == getter(:1092) |
| `surfaceContainerLow` | `surfaceRaised` | :314 / :1092 |
| `surfaceContainer` | `surfaceSunken` | :315 == surfaceContainerHigh(:316) == getter(:1095) |
| `surfaceContainerHigh` | `surfaceSunken` | :316 / :1095 |
| `surfaceContainerHighest` | `surfaceActive` | :317 / :1098 |

`primaryContainer` 与 `infoContainer` 同值（浅蓝底 + 深蓝前景，原注释即「头像底/选中底/AI 标记」），映射到 `semanticInfo` 是唯一零色差选择；若日后要把「选中态」改成 `.impeccable.md` 规定的 `surfaceActive` 中性药丸，那是独立设计票，不在本迁移范围。

### 替换纪律（防误伤）
脚本只重写两种形式，避免动到 `app_theme.dart` 里的字段声明 / 构造参数（那是 LCC-06 的删除范围）：
- 成员访问 `.token`（`\.token\b`）
- 主题字符串键 `'token'` / `"token"`（保留引号）

`app_theme.dart` 整文件排除（LCC-06 删除兼容块 `:522-536` + 旧字段 `:1007-1084`）。5 处注释中的旧名一并改为新名，使 grep 闸门真正归零、文档不 stale。

_— 定位（volatile）—_
- 兼容块：`frontend/lib/shared/theme/app_theme.dart:522-536`（标"兼容，新代码勿用"）
- 旧字段声明：`app_theme.dart:1007-1084`（primaryContainer/secondaryContainer/tertiaryContainer/errorContainer/surfaceContainer*/infoContainer + on*）
- 新令牌 getter：`app_theme.dart:1092-1131`（surfaceRaised/surfaceSunken/surfaceActive/semantic*/cta）
- 消费者：全量 grep 15 个旧名于 `frontend/lib` 排除 `app_theme.dart` → 42 文件
