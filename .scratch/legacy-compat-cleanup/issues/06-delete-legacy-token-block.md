# 06: 删除 app_theme 兼容令牌块

**What to build:** `app_theme.dart` 中标注"兼容，新代码勿用"的旧 M3 令牌定义块整段删除；仅保留 ADR-0044 新令牌。

**Blocked by:** 05（已 done）

**Status:** done

## 验收清单

- [x] `app_theme` 中无旧 M3 令牌名定义（grep `surfaceContainer|*Container|infoContainer` 在 `app_theme.dart` 内零命中，仅剩 ADR-0044 语义/表面字段）。
- [x] 定向 grep 全仓旧令牌名（定义+引用）命中数归零：除 `feature_relationship_tree.html` 中"已清理"行对 `primaryContainer 等` 的**描述性引用**（说明被删的是什么，非代码引用）外，lib/ 注释/后端零命中。
- [x] `flutter analyze` 通过（No issues found!）。
- [x] `flutter test` 552/552 通过（与 05 同基线，无回归）。

## 实施要点（commit `1405e57`）

- 删除 `_customColors()` 兼容字符串块（原 `:522-536`）14 条旧角色名键（`'infoContainer'`/`'primaryContainer'`/`'surfaceContainer*'` 等）。
- 折叠 15 个 M3 容器字段 → 11 个 ADR-0044 字段：
  - `surfaceContainerLowest`/`surfaceContainerLow` → `surfaceRaised`
  - `surfaceContainer`/`surfaceContainerHigh` → `surfaceSunken`
  - `surfaceContainerHighest` → `surfaceActive`
  - `primaryContainer`/`infoContainer` → `semanticInfo`（字节目值逐字节相同 `0xFFDCE7FA`/`0xFF1D4E9C`）
  - `onPrimaryContainer`/`onInfoContainer` → `semanticInfoFg`
  - `secondaryContainer`/`errorContainer`/`tertiaryContainer` → `semanticWarning`/`semanticError`/`semanticPositive`（1:1 改名）
  - 对应 `on*` 改名跟随
- 删除 11 个冗余 getter（`surfaceRaised`/`surfaceSunken`/`surfaceActive`/`semantic*` 现已是字段）。
- light/dark builder 改写；`muted: c.surfaceContainer` → `c.surfaceSunken`。
- 注释（`:444-457`）改为"命名以 `.impeccable.md` public 令牌名为准（语义名优先）"，去掉"旧角色名 key 保留做兼容"措辞。
- **色值零变化**：所有映射底层 hex 逐字节相同，纯词法替换，视觉无变化（详见 05 映射表）。

## 文档漂移同步

- `feature_relationship_tree.html:183`：旧令牌块行改 `v-ok`/"已清理"，注明 LCC-05/06 完成。
- `CODE_AUDIT_REPORT.md:171`/`184`：双视觉令牌条目标注已清理；P1 计划行标"已执行"。
- `docs/adr/0051-empty-state-language.md:31`：`surfaceContainerLow` 代码例 → `surfaceRaised`（与 `app_empty_state.dart` 实际用法一致）。

_— 定位（volatile，仅供本次实施）—_
- `frontend/lib/shared/theme/app_theme.dart`（核心删改，`1405e57`）
