# 03: media_gallery 环节内联增删素材项

Parent: docs/specs/teacher-courseware-round-2.md（ADR-0067 第二轮 · 编辑器方向）

**What to build:** 在媒体画廊环节的编辑器对话框里，教师能就地加 / 删素材项（加用首轮已落地的素材 picker，本轮补「删」并加固），改动经 `updateSections` 持久化；演示页画廊同步反映增删；「素材已移除」占位（决策 10）逻辑不受影响。

**Blocked by:** None（can start immediately）。

**Status:** done

**Done:** T03 已验收。编辑器对话框的内联增 / 删素材项逻辑已在 T02 的对话框重写中落地（`_addAsset` 复用 `showCoursewareAssetPicker`；`_removeItem` 删 `payload['items']`；`_save` 对非 practice 环节原样透传 `_draft.payload`），本轮按 ticket 补齐**验证与 widget 测试**，确认全链路。
- 演示页画廊（`section_media_gallery.dart`）本就按增删后 payload 渲染：有效 id → 图 + caption，失效 id → 「素材已移除」占位（决策 10），空 items → 空态 + 上传引导（不降级示意图）——本轮**未改动**、行为不变。
- 新增前端 widget 测试（共 +3）：
  - 编辑器对话框内联「添加素材项」→ 开 picker 选图 → 保存后 `updateSections` 落库、`payload.items` 项数 +1 且含新 `asset_id`；
  - 内联「删除素材项」→ 保存后项数 -1、旧项不再出现；
  - 演示页画廊：2 个有效素材 → 各自 caption 出现、无「素材已移除」占位。
- 测试 harness：`_pumpEditor` 新增 `assets` 参数并 override `coursewareAssetsProvider`，与演示页测试保持一致（数据走 provider，R4）。
- 验收：`flutter analyze lib/features/courseware` → No issues；前端 25 项（editor 9 + present 14 + practice 2）全绿；后端无改动、25 项 courseware 测试保持全绿。

- [x] 编辑器对话框针对 media_gallery 环节，提供内联「添加素材项」（复用既有 picker）与「删除素材项」操作。
- [x] 增 / 删经 `updateSections` 持久化；重开编辑器 / 演示页画廊反映最新项集合。
- [x] 演示页画廊正确展示增删后的素材项。
- [x] 当某素材在别处被删，引用它的环节仍显示「素材已移除」占位（沿用首轮决策 10，不被本轮改动破坏）。
- [x] 全程不引入 Material 系控件；编辑器对话框单文件 ≤400 行；`presentation/` 不 import `*/data/`。
- [x] 前端 widget 测试断言：内联添加项持久化并出现在画廊；内联删除项持久化且不再出现；占位行为不变。
