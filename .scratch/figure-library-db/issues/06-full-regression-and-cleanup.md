# 06: 全链路回归与清理

**What to build:** 全场景走通新形态并移除双源遗留（代码 `FIGURES` 常量、`gen_figures.py`、`figures.dart` 生成物、`test_frontend_figures_are_not_stale` parity 锁）。

**Blocked by:** 02, 03, 04, 05（须所有改造票完成再收口）

**Status:** ready-for-agent

## 验收
- [ ] 旧题 / 课件 / AI interactive_scene 全部从新形态渲染，无回归。
- [ ] SceneSpec 生产/消费代码中不再出现 inputs/controls/narrative/outputs/title/editable 字段。
- [ ] 退役 `gen_figures.py` 与 `test_frontend_figures_are_not_stale` parity 锁。
- [ ] 移除代码 `FIGURES` 常量（`scene_figures.py` 几何源改由 DB 承担）与 `SCENE_LIBRARY` 残留 axis 字段（若有）。
- [ ] `flutter analyze` 0 issue；全仓 `flutter test` + 后端 pytest 无回归。

## 纪律
- 不破坏「题库/错题/AI 讲解现有观感」（快照不可变）。
