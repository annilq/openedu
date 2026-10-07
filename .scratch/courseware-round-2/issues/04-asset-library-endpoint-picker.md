# 04: 素材库检索端点 + picker 接入

Parent: docs/specs/teacher-courseware-round-2.md（ADR-0067 第二轮 · 素材库方向）

**What to build:** 新增教师「素材库」检索端点：跨课件列出该教师自己传过的全部课件素材，可按知识点 / 文件名过滤；素材 picker 在「本课件已传」之外并列展示「我的素材库」，选择协议与首轮一致（同一 `CoursewareAsset` 选择回执）。让同一张图不必传第二次。

**Blocked by:** None（can start immediately）。

**Status:** done

## Done note（2026-10-07）
T04 全链路落地并验收：
- 后端：`CoursewareAsset` 模型加 `knowledge_point_id`（可空索引列）；`db.py` 幂等迁移补列（SQLite `ADD COLUMN` / Postgres `IF NOT EXISTS`，旧库启动期自动补齐）。`GET /courseware/assets` 扩展为检索端点，支持 `knowledge_point` / `filename` 查询参数，委托新增 `asset_service.search_assets`；传 `knowledge_point` 时经 `require_owned(KnowledgePoint)` 做归属校验，跨教师返回 403（不降级成 404）。`CoursewareAssetResp` 回传 `knowledge_point_id`。
- 前端：`CoursewareAssetModel` 加 `knowledgePointId`；`CoursewareRepository.getAssets` 加 `knowledgePointId` / `filename` 可选参数并拼查询串；新增 `coursewareAssetLibraryProvider` family（按知识点/文件名服务端过滤）；picker 新增文件名检索框（`AppTextField`，按 `asset-search` key 定位），沿用同一选择协议回传 `{asset_id, caption}`。
- 测试：后端 `test_courseware_assets.py` 增 4 例（教师域隔离 / 按知识点过滤且回传 kp_id / 按文件名过滤 / 跨教师 kp 403=403 SYS_10002）；前端 editor 测试增 2 例（picker 并列展示素材库 + 选择回执含 asset_id；文件名检索框过滤素材库）。`tests/ai/test_layering_invariants.py` 通过。
- 验证：`flutter analyze lib/features/courseware` 0 issue；后端 courseware 模块 + 分层守卫 39 passed；前端 editor/present/practice 27 passed。
- 文件行数：picker 202 / dialog 275 / service 196 / router 79 / schemas 35，均 ≤400（ADR-0058）。
