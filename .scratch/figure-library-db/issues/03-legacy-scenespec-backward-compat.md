# 03: 旧 SceneSpec 向后兼容 + 回归

**What to build:** 已落库的旧形 `scene_spec`（含 inputs/controls/narrative/title/editable 或 figure 引用）在 02 改造后仍能正确渲染，几何不丢、观感不变。

**Blocked by:** 02（需新渲染器已就位才能验证旧数据经适配后仍正确）

**Status:** done

## 适配层
- 把旧 inputs[points]/figure 引用等映射为新 `{kind, points, edges}`；`edges` 缺省按顶点顺序补默认（旧数据无 edges）。
- 旧 figure 引用若仍能对应 DB 图库，则补注入 points+edges；对应不上则回退 house（极端兜底）。

## 快照不可变
- 改库（figure_library）/ 改外壳（SCENE_LIBRARY）**不影响**已落库 `Question.scene_spec` 的渲染（ADR-0073 红线）。

## 验收
- [x] 适配层把旧 scene_spec 映射为新形态；edges 按顶点顺序补默认。
- [x] 存量 `Question.scene_spec` 样例经适配后渲染正确、几何不丢。
- [x] 快照不可变网守：改库/改外壳后已落库 scene 渲染不变。
- [x] 断言旧 controls/narrative 不再被读取、house 仅极端兜底。
- [x] 全仓 `flutter test` / 后端 pytest 无回归。
