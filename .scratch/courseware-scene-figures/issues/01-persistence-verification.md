# 01: 端到端持久化通路验证（tracer bullet，先证伪）

**What to build:** 证明「课件环节能携带一组图形」这件事**真的存得下来也读得回来**——教师保存一个环节，其场景数据里带着 `optionGroup`（`curated` + `items`，`items` 内含展开好的顶点），保存后重新拉取该课件，这几个键与顺序完好无损。

**Blocked by:** 无（可立即开工；本票是全案的证伪票，最先做）

**Status:** done

## 为什么排在第一

后面四票全部建立在「环节场景是透传结构、后端零改动」这一条之上，而该结论目前**只是读代码得出的**，没有端到端跑过。若其实存不下来（序列化剥字段、模型层吞 null、快照合并覆盖），后四票全废。先花一张票证伪最省钱。

## 要验的三段通路

1. **写**：编辑环节场景 → 把带 `optionGroup` 的结构交出去 → 保存成功。
2. **读**：重新拉取同一课件同一环节 → `curated` / `items` / `points` / `figureKey` / `caption` / `defaultAxisAngle` 全在，**`items` 顺序不变**（编排意图就落在顺序里）。
3. **不回写**：知识点上的默认讲解快照前后一致——动的是环节副本，不是知识点场景（ADR-0073）。

## 已知的两个可疑点（逐条确认，别假设）

- 环节模型的 `copyWith` 用哨兵值区分「没传」与「显式清空」：用 `??` 合并会把显式清空吞成"没传"，导致删掉图形组时删不掉。
  → **已确认无此问题**：`copyWith(scene: null)` 真的清成 null（`_unset` 哨兵生效），见 Done note 的测试证据。
- 环节场景是**关联知识点时的快照副本**：要确认保存环节时不会被知识点场景整体覆盖回单份默认讲解。
  → **已确认无此问题**：保存带 `optionGroup` 的环节后，知识点 `scenes` 前后一致（零回写）。

## 验收

- [x] 带 `optionGroup` 的环节保存成功（无 422、无字段被静默剥离）。
- [x] 重新拉取后 `curated == true`、`items` 长度与顺序与保存前一致、`points` 内顶点数组完整（非空、非被压平成字符串）。
- [x] 反向：清空图形组后保存 → 重新拉取确实为空（哨兵语义正确，没被 `??` 吞掉）。
- [x] 知识点场景快照前后一致（未回写）。
- [x] **给出明确结论**：后端是否需要改动。
  - [x] **不需要** → 记下结论与证据，放行 02–05。

## Done note（2026-10-09）

### 结论：**后端零改动**，前提成立，放行 02–05。

环节场景确为裸 dict 透传：`PUT /courseware/{id}/sections` 整份落库（`service._section_to_dict`
原样写 `"scene": s.scene`），`GET` 经 `CoursewareSection.model_validate` 原样回读，不剥 key、
不重排、不把显式 `null` 合并成「没传」。前端模型层同理，`copyWith` 的 `_unset` 哨兵语义正确。

### 证据（命令 → 结果）

后端（worktree 无 `.venv`/`.env`，`.env` 本就不存在故无需 mv；借用主仓库 `.venv` 的 pytest/ruff）：

```
cd backend
/Users/annilq/Documents/develop/openedu/backend/.venv/bin/pytest \
  tests/features/courseware/test_courseware_scene_persistence.py --basetemp=/tmp/cwscene01 -q
→ 3 passed in 0.33s

/Users/annilq/Documents/develop/openedu/backend/.venv/bin/pytest tests/features/courseware \
  --basetemp=/tmp/cwscene01b -q
→ 48 passed in 3.32s（含本票 3 条，无回归）

/Users/annilq/Documents/develop/openedu/backend/.venv/bin/ruff check .
→ All checks passed!
```

前端（`flutter pub get` 后，代理已关）：

```
cd frontend
no_proxy="127.0.0.1,localhost,::1" NO_PROXY="127.0.0.1,localhost,::1" \
  /Users/annilq/Documents/fulttersdk/flutter/bin/flutter test test/courseware_section_model_test.dart
→ 00:00 +4: All tests passed!（4 条）

同上全量 flutter test
→ +410 ~1 -4：4 条失败均为**集成分支 tip 上既有**的失败，与本票无关：
    · no_bare_gesture_guard_test.dart（features/assistant/.../draggable_assistant_fab.dart:118 裸 GestureDetector）
    · courseware_editor_page_test.dart 3 条（编辑弹窗已无「选择讲解模板」/「未关联（点此选择）」文案，
      源于 aa23a29「演示页按配置显示，移除交互场景的自动填充」后的既有落差）

flutter analyze
→ 3 issues found，全部落在 analytics_screen_test.dart / scene_library_associate_dialog_test.dart（既有），
  本票新增文件 0 issue。
```

### 新增的测试

- `backend/tests/features/courseware/test_courseware_scene_persistence.py`（3 条）
  - 带 `optionGroup`（`curated=True` + 3 个有序条目，条目含 `label:""` / `caption` / `figureKey` /
    `points`（二维顶点）/ `defaultAxisAngle`）的环节经 `PUT /sections` 写入、`GET` 回读后
    `curated` 在、条目数量与顺序一致、`points` 非空且每个顶点仍是 `[x, y]`（没被压平）。
  - 显式 `scene: null` 覆盖保存 → 回读确实为 `null`（显式清空没被 `??` 吞）。
  - 知识点 `scenes` 前后一致（零回写，ADR-0073）。
- `frontend/test/courseware_section_model_test.dart`（4 条）
  - `toJson()` → `fromJson()` 往返后 `scene['optionGroup']` 的 `curated` / `items` / `points` / 顺序全部保持。
  - 无 scene 的环节往返后仍为 null（不臆造）。
  - `copyWith()` 不传 scene 时保留原值；`copyWith(scene: null)` 真的清成 null 且 `toJson()['scene']` 为 null（键仍在）。

### 未做的事（本票纪律）

只验证不做功能：未引入编辑器 UI、未改渲染层、未改后端 schema / service / 端点。

## 纪律

- 本票**只验证，不做功能**：不引入编辑器 UI、不改渲染层。验证手段可以是集成/契约测试，也可以是联调手工验证（后端 `--host 0.0.0.0` + 前端填局域网 IP），结论写进本文件的 Done note。
- 若结论是「需要改后端」，后面四票的规模都会变，必须在开工前摊开重估。
