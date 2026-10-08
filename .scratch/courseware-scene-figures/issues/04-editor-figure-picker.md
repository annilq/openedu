# 04: 课件编辑器勾选多图 + 写入 optionGroup

**What to build:** 教师的入口。环节关联好场景后，让他**勾选要给哪些图形、并能排出顺序**，结果写进本环节的场景数据；勾选的产出是一份结构化的图形组，讲课页据此摆出多张图。

**Blocked by:** 无（本票产出的是**数据**，用假仓库断言保存出去的内容即可自证，不必等渲染层；可与 02 / 03 并行开工）

**Status:** done

## UI 落点

- 挂在课件环节编辑弹窗的关联场景区块之后。
- **新增独立文件**承载选择器——`courseware_section_edit_dialog` 已 515 行，不得继续堆高（ADR-0058）。
- 仅当已关联场景的类型是轴对称（`reflection`）时才展示——其它场景类型没有平面图形语义，摆一个图形选择器是误导。
- 勾选即定序：用**勾选顺序**（而非库顺序）决定条目顺序；提供上移/下移或等价的可达入口。选中态沿用全站统一的强调色描边语言。
- 未选任何图形时给出空态与引导（告诉教师"选了才会同屏演示多张"）。

## 数据写入（契约见 ADR-0076 §2.1 / §2.2）

```jsonc
section.scene['optionGroup'] = {
  "curated": true,
  "items": [ { "label": "", "caption": "<图形中文名>", "figureKey": "<key>",
               "points": [[x,y]…], "defaultAxisAngle": <deg> } ]
}
```

来自原型/契约的形状，落地时以这份为准：

- **`points` 必须在保存时展开写入**，取自前端图形库（它由后端图形定义在构建期生成，前后端一致性有测试钉住）。只存 key 让渲染层运行时回查，会让"第一次打开是空的"变成常态——课堂演示不能依赖一次查询。
- `label` 留空串（课件语境没有 A/B/C 选项），`caption` = 图形中文名。
- **数量闸门**：勾 ≤1 张 → **删掉**图形组（回落到现状单场景路径）；勾 ≥2 张才写。这正是"按数据动态分派"。
- 只在环节的草稿副本上操作；**严禁**回写知识点上的场景（ADR-0073）。注意环节模型的 `copyWith` 用哨兵值区分「没传」与「显式清空」，别用 `??` 把显式清空吞掉（ticket 01 已确认该语义）。

## 验收（输入侧接缝：编辑器 + 假仓库，断言保存出去的那份数据）

- [x] 勾 2 张 → 图形组条目长度 2 且顺序 == 勾选顺序；保存 → 重开编辑器 → 回读一致。
- [x] 勾 1 张 / 0 张 → 图形组被移除，单场景渲染路径不变。
- [x] 未关联场景或场景类型不是轴对称時，该选择器不出现。
- [x] `points` 已展开（断言条目里有真实顶点数组，不是空、不是只有 key）。
- [x] 知识点场景未被改动（可断言关联前后快照一致）。
- [x] 新增 widget 测试 ≥3 例（勾选定序 / ≤1 张回落 / 非轴对称不出现）。
- [x] 静态检查两文件 0 issue。

## Done note（实现结果）

**新增** `frontend/lib/features/courseware/presentation/pages/section_scene_figures_picker.dart`
（361 行）：图形卡网格（11 个 `kFigureShapes` 预设 + 描边缩略图）+ 已选顺序行
（上移 / 下移 / 移除）+ 空态引导（`AppEmptyState.inline` + steps）。

**改动** `courseware_section_edit_dialog.dart`（371 → 394 行，仍在 400 以内）：关联
场景区块之后挂入，仅 `_draft.scene['kind'] == 'reflection'` 时展示；改写走既有的
`_associateScene`（`copyWith(scene: Map.from(...))`，传新 Map、不吞 null）。

**一个必须记下的设计约束**（踩过一次）：`<2 张删 optionGroup 键` 这条闸门意味着
「只勾了 1 张」这个中间态**写不进场景**——若以场景为唯一真相，教师勾第一张时界面
不会有任何反应（勾选被自己写的闸门吃掉）。故选择器是 `StatefulWidget`：已选列表是
本地状态，只在 ≥2 张时落进场景；`didUpdateWidget` 用「场景里的条目 key 是否 == 我们
最近一次写出去的 key」分辨「外部换了场景」与「自己的回声」，避免空表把草稿冲掉。

**测试** `frontend/test/section_scene_figures_picker_test.dart`（377 行，7 例）：真
编辑器页 + 假仓库，断言 `repo.lastUpdated.first.scene`。顺序断言刻意用**非库序**的
勾选序列（先正方形后房子）；零回写那条用例让环节的 scene 与知识点模板**共用一个 Map
实例**（就地写会立刻被抓）。不套 Material（中文 `MaterialLocalizations` 委托 + ShadApp
+ CupertinoApp），`setSurfaceSize(1280×1400)`。

**结果**：7 例全绿；`flutter analyze` 仍是既有 3 条（都在既有测试文件里），两文件 0 issue；
全量 `flutter test` 434 passed / 4 failed，4 条失败与基线**逐字一致**
（`courseware_editor_page_test.dart` 3 条仍失败在 751 / 765 / 805 行的旧文案断言；
`no_bare_gesture_guard_test.dart` 1 条仍是 `draggable_assistant_fab.dart:118`），
未新增、也未改变失败形态。
