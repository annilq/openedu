# 05: 迁移遗留 M3 视觉令牌（23 文件）

**What to build:** 23 个仍在使用旧 M3 兼容令牌名（`infoContainer`/`primaryContainer`/`surfaceContainer` 等）的文件，全部改用 ADR-0044 新令牌名；旧名在消费者侧零引用。宽重构：新名已存在，本票只做迁移批次。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 全仓 grep 旧令牌名集合命中数（消费者侧）归零。
- [ ] 23 个文件的视觉效果经 `dev/theme_preview.dart` 目视无缺色/无报错。
- [ ] `flutter analyze` 通过。

_— 定位（volatile，仅供本次实施）—_
- 兼容块：`frontend/lib/shared/theme/app_theme.dart:522-536`（标"兼容，新代码勿用"）
- 消费者 23 文件：grep `infoContainer|primaryContainer|onPrimaryContainer|secondaryContainer|onSecondaryContainer|tertiaryContainer|onTertiaryContainer|errorContainer|onErrorContainer|surfaceContainerLowest|surfaceContainerHigh|surfaceContainerHighest` 于 `frontend/lib`
- 新令牌名见同文件上方 ADR-0044 定义
