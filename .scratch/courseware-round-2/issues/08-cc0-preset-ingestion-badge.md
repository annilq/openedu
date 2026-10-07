# 08: CC0 预置包入库 + 标注与来源说明

Parent: docs/specs/teacher-courseware-round-2.md（ADR-0067 第二轮 · 素材库方向）

**What to build:** 维护期把平台预置的 CC0 图片按「逐张核授权 + 记录来源」入库，打 `source=platform_cc0` 标记（含来源 URL 与许可类型），随仓库离线分发（不运行时联网）；picker 中 CC0 与自有素材并列、带 CC0 角标，点开可见来源 / 许可说明。符合 ADR-0067 §3.5 / §5 的硬边界。

**Blocked by:** 04（素材库检索端点 + picker 接入）——CC0 角标与来源说明依赖素材库 picker 的并列展示能力。

**Status:** done

- [x] 维护期 seed 脚本入库 CC0 图片，每条带 `source=platform_cc0`、来源 URL、许可类型；随仓库分发、不运行时联网拉取。
- [x] picker 在「我的素材库」中把 CC0 与自有素材并列展示，CC0 带可见角标。
- [x] 点开 CC0 素材显示来源 URL 与许可说明，教师可放心用于课堂。
- [x] 自有（非 CC0）素材删除后，引用环节仍显示「素材已移除」占位（沿用首轮决策 10，不被破坏）。
- [x] 全程不引入 Material 系控件；`presentation/` 不 import `*/data/`。
- [x] 测试断言：seed 后素材带 `source=platform_cc0` + 来源 + 许可；picker 角标可见；来源 / 许可详情可读；无任何运行时联网调用；自有素材删除占位行为不变。

**Done note (2026-10):** 后端 `CoursewareAsset` 加 `source`(默认 user_uploaded)/`source_url`/`license` 三列，`run_migrations` 补列（ALTER+PRAGMA 幂等，复用老库迁移范式）；`asset_service`：`search_assets` 含 `source=platform_cc0`（所有教师可见、与自有素材并列）、`asset_file` 经 `_owned_or_cc0` 对任意教师放行原图、`delete_asset` 拦 CC0（403 FORBIDDEN）。seed：`seed_cc0.py` + `seeds/courseware_cc0/manifest.json` + 离线占位 PNG + `scripts/seed_courseware_cc0.py`（CLI），幂等（同名跳过）。前端 `courseware_asset.dart` 加 `source/sourceUrl/license`+`isPlatformCc0`；picker 给 CC0 加「CC0」角标 + 许可/来源明细行。后端 `test_cc0_ingestion.py` 8 测试全绿（seed 字段/可见/原图离线/删 CC0 拦 403/幂等/默认 user_uploaded/老库迁移补列）；前端 picker 2 测试全绿。`courseware_editor_page_test` 17 全绿，三件套 40 全绿，analyze 0 issue；后端 courseware+core migration 52 全绿。
