# 06: 全链路回归与清理

**What to build:** 全场景走通新形态并移除双源遗留（代码 `FIGURES` 常量、`gen_figures.py`、`figures.dart` 生成物、`test_frontend_figures_are_not_stale` parity 锁）。

**Blocked by:** 02, 03, 04, 05（须所有改造票完成再收口）

**Status:** done（T06-A `608cac5` 后端几何单源 + 退役 parity 锁/gen_figures.py；T06-B `7f77d0d` 前端退役图形常量双源）

## 验收
- [x] 旧题 / 课件 / AI interactive_scene 全部从新形态渲染，无回归。
      （`scene_legacy_compat_test` 钉住旧形 spec 读取侧：几何不丢、轴初值仍采信、文案取外壳；
      `scene_library_t04_test` 钉住旧题 / 详情页路径不抛异常）
- [x] SceneSpec 生产/消费代码中不再出现 inputs/controls/narrative/outputs/title/editable 字段。
      （grep 复核后仅剩两处**合法例外**：T03 适配层 `reflection_scene_data.adaptSceneSpec`（专为读
      存量快照）、kind 外壳读取器 `scene_shells.dart`（读后端下发的外壳默认值）。
      详情页预览原先自行改写 spec 塞 `editable/controls/narrative` 已改为
      `SceneInterpreter.showAxisControls` 展示开关。）
- [x] 退役 `gen_figures.py` 与 `test_frontend_figures_are_not_stale` parity 锁。（T06-A）
- [x] 移除代码 `FIGURES` 常量（`scene_figures.py` 几何源改由 DB 承担）与 `SCENE_LIBRARY` 残留 axis 字段（若有）。
      （后端仅剩 `BUILTIN_FIGURE_SEED`（首次安装播种用，带 note、无 axis）；`axis_angles`/`axis_count`/
      `is_axisymmetric` 全仓零命中；`FIGURES` 只在 `scene_fusion.py` 的注释里作为「不再查的旧常量」被提及。）
- [x] `flutter analyze` 0 issue；全仓 `flutter test` + 后端 pytest 无回归。
      （analyze `No issues found!`；flutter test **519 passed / 1 failed**，唯一失败是**既有**
      `analytics_charts_test.dart` 的 fl_chart 护栏（`workbench_analysis`/`workbench_glance` 裸用
      fl_chart），在本 epic 之前就已红、与本轮无关；后端 `pytest` 795 passed, 2 skipped。）

## 纪律
- 不破坏「题库/错题/AI 讲解现有观感」（快照不可变）：T03 适配层保留，快照零回写。
- 文件规模棘轮（ADR-0058）：`reflection_scene.dart` 已从 567 降到 438，`_baseline` 同步下调；
  新增 `scene_figure_tile.dart`（134 行）为拆行数而抽出。
