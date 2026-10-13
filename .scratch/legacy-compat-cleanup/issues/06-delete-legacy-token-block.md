# 06: 删除 app_theme 兼容令牌块

**What to build:** `app_theme.dart` 中标注"兼容，新代码勿用"的旧 M3 令牌定义块整段删除；仅保留 ADR-0044 新令牌。

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] `app_theme` 中无旧 M3 令牌名定义。
- [ ] 定向 grep 全仓旧令牌名（定义+引用）命中数归零。
- [ ] `flutter analyze` 通过。

_— 定位（volatile，仅供本次实施）—_
- `frontend/lib/shared/theme/app_theme.dart:522-536`
