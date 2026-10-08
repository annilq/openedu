# 课件编辑器第二轮 (courseware-round-2) · Tickets 索引

> 来源：ADR-0067 第二轮课件编辑器 spec `docs/specs/teacher-courseware-round-2.md`。
> 本地 `.scratch` 文件（未建 GitHub issue）。每张 ticket 含 `What to build` / `Blocked by` / `Status` / 验收清单。

## 范围
首轮课件编辑器已落地基础能力（环节 CRUD、演示、练习、素材 picker）。本轮 T01–T09 在四个方向深化：
编辑器交互（拖拽重排 / 批量删、多段话术、AI 重起草 diff）、素材库（检索端点、CC0 预置）、练习深化（提示级别）、投影交互。

## Tickets 状态（全 done）

- **01 编辑器环节拖拽重排 + 批量删除** ✅ done——`editor_section_list.dart` + 重排/批量删回调 + 新测试；修正 `AppTopBar` 40px trailing 槽溢出。
- **02 话术多段化 + 轻量重点标注** ✅ done——`CoursewareSection.script_segments`、`courseware_script_view.dart` 逐段渲染、编辑器对话框重写（增删段/切重点），旧单串课件经 `displaySegments` 退化兼容。
- **03 media_gallery 环节内联增删素材项** ✅ done——编辑器内联增/删素材项经 `updateSections` 持久化；演示画廊同步；「素材已移除」占位逻辑不变；补 3 例 widget 测试。
- **04 素材库检索端点 + picker 接入** ✅ done——`CoursewareAsset.knowledge_point_id` + 幂等迁移；`GET /courseware/assets` 扩展检索（知识点/文件名，跨教师 403）；前端素材库并列展示 + 文件名检索。
- **05 练习提示级别选择 + tutor 分级驱动 + 反馈卡片** ✅ done——`AssistantCoursewareContext.extra` 透传 hint_level（方向/条件/下一步），反馈卡重申不建任务/不落作答；分级由提示词驱动，无需后端新逻辑。
- **06 投影交互：键盘翻页 + 字号升档 + 轻过渡 + 安全区** ✅ done——键盘/翻页笔翻页与按钮并存；字号随 `contentWide=1080` 升档；环节切换轻过渡（尊重 reduced-motion）；横屏安全区收边；复用 `AppPushedPage` 全屏壳。
- **07 AI 重起草 diff 预览 + 逐段接受** ✅ done——`draft_sections` 返回逐段 diff；编辑器渲染并逐段接受，写回同一课件（不新建副本）。
- **08 CC0 预置包入库 + 标注与来源说明** ✅ done——维护期 seed 入库 CC0 图（`source=platform_cc0` + 来源 URL + 许可），随仓库分发不运行时联网；picker 角标并列展示。
- **09 课件编辑器进入行为改造（追认）** ✅ done（commit `e7c539f`）——进入不自动 `createCourseware`，空态「新增课件信息」显式发起；已有课件直接展示不重起草；补 3 例测试闭合历史缺口。

## 验证纪律（各票共同）
- `flutter analyze lib/features/courseware` 0 issue；
- 前端 editor / present / practice 测试全绿；
- 后端 courseware 模块 + 分层守卫（`tests/ai/test_layering_invariants.py`）通过；
- 全程不引入 Material 系控件；`presentation/` 不 import `*/data/`；编辑器 widget 单文件 ≤400 行（ADR-0058）。
