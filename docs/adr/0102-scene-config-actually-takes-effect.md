# ADR-0102 让「关联了场景」真的生效：lacuna 几何位置 + 四元组不全的通知识点

- 状态：已采纳
- 日期：2026-10-20
- 关联：ADR-0091（SceneSpec 只认新形，旧形一律拒绝）、ADR-0061 §U（`scene_spec_for_read` 唯一读路径）、ADR-0089 §4（答疑三层识别 L0 门控）、ADR-0101（路由）

## 1. 背景

教师报障：知识点「图形的运动（轴对称）」**已关联场景**，但助手答「出一道选择题」时不出图。
按 ADR-0101 修完路由后，继续沿链路查，发现**另外两道独立的闸门也全程关闭**——本机
`app.db` 实测，不是任何一份场景能用，而是**全部 10 份都不能用**。

### 1.1 闸门 A：迁移脚本认不出几何真正的所在

旧编辑器把几何当成「可调输入项」写进 `inputs`，而不是顶层 `points`：

```json
{"kind":"reflection","title":"…","inputs":[
  {"key":"axisAngle","value":90.0}, {"key":"axisX","value":0.5},
  {"key":"points","value":[[0.3,0.7],[0.7,0.7],[0.7,0.45],[0.5,0.25],[0.3,0.45]]},
  {"key":"figure","value":"house"}],
 "controls":{…},"narrative":"…"}
```

`migrate_scene_specs.py` 的 `_rewrite` 只看**顶层** `points`/`edges`/`optionGroup`：

```
$ python scripts/migrate_scene_specs.py --check
扫描 10 份 spec：迁移 0，已是新形 0，跳过 10
[跳过] KnowledgePoint.scenes[0]#357dd912…: 不可迁移（无几何 / 畸形 / 非 dict）
[跳过] Question.scene_spec#7fcfdccc…:      （同上）
...                                            ← 10/10 全跳
```

而读路径（ADR-0091）因 `inputs` 属旧形键，**一律拒绝整份 spec**：

```
normalize_scene_spec(模板) → None
fuse_scene_spec(模板)      → None
```

两条路一起，把「关联了场景」变成空话——**配置得再对也没有任何链路读得到它**。

### 1.2 闸门 B：四元组不全 → 知识点恒查不到

`find_knowledge_point` 按 `(teacher_id, subject, grade, name, semester)` **严格等值**匹配，
学期走「精确 → 整学年回落」。而答疑侧 L0 门控拿到的四元组常常是残的：

- 用户原话「请为「图形的运动（轴对称）」出一道选择题」**没写学科、没写年级**；
- `tutor/agent.py` 的 `detect_subject(message)` 是 `for s in SUBJECTS: if s in text` → 空串；
- `grade` 同理为 0。

实测：

```
subject='数学' grade=4 semester='下学期' → ('图形的运动（轴对称）', 4, '下学期')   ✅
subject=''     grade=0                  → None                                    ❌
resolve_interactive_scene(subject='', grade=0) → None（L0 直接不放行）
```

雪上加霜：库里**没有 `semester=''` 的整学年行**（`整学年行数: 0`），所以「回落整学年」
这一层在本库是死路——四元组必须**五格全中**才行，而答疑侧注定缺两格。

## 2. 决策

### 2.1 迁移脚本认 `inputs` 里的几何（不改读路径）

`_geometry_from_inputs(spec["inputs"])` 取 `{key:'points', value:[…]}` 与
`{key:'figure', value:key}`：

- 有顶点 → 迁成新形 `figure`；**`edges` 缺省按顶点顺序闭合**（旧 `inputs` 形没有
  edges，连接关系隐含在顶点顺序里——因为它不是「畸形」就丢掉整份快照，正是本次要修的）；
- 身份键以**顶点反查图库**为权威；反查落空时才用 `inputs` 里记的 `figure` 值兜一层
  （它比 `user_<hash>` 可读，且仍是稳定键）；
- `inputs` 等旧键仍按原规则**丢弃**——读路径的「不做双读」不被破坏。

结果：`--check` 从「迁移 0 / 跳过 10」变成「**迁移 10 / 跳过 0**，图库反查命中 22」，
跑 `--apply` 后复查「已是新形 10」，幂等成立；两份知识点模板 `normalize_scene_spec`
均返回带 `figure` 的合法 spec。

### 2.2 `find_knowledge_point` 增加 `allow_partial`（默认关）

新增关键字参数 `allow_partial: bool = False`：

- **默认关**：出题侧（`specs.figure_catalog_for_question` / `figure_stamp`）总带完整
  四元组，放开只会把别的年级的知识点误当命中——不存在「猜」。
- **答疑 L0 显式开**：名字已经是强证据（同一老师下重名极少），比「查不到就不出图」正确。
  过滤规则不变的部分照旧：归属 `teacher_id` 不可穿越、`name` **完全相等**（不做子串
  模糊，那才是猜）；有值的 `subject`/`grade`/`semester` 仍参与过滤。
- **结果确定**：候选行按「配了 `scenes` 者优先 → 同学期者优先 → 创建时间」排序。
  问场景就该能找到场景的那一行（同名多学期时尤其重要）。

## 3. 后果

- 「关联了场景」从「配置了但全链路读不到」变成「配置即生效」——这是本次报障的实质修复。
- 代价：`find_knowledge_point` 多一个分支。缓解方式是把「放宽」做成**调用方显式选择**，
  而非默认行为；默认路径与改动前逐字节等价（既有 10 项 `test_migrate_scene_specs`
  与全部 `test_scene_*` 不改一行仍绿）。
- 代价：迁移脚本多一条识别路径。它只在「顶层无几何」时才跑，且产物必过
  `normalize_scene_spec` 自检门——过不了就跳过并留痕，绝不写半份几何（原纪律不变）。

## 4. 备选（否决）

- **改成读路径双读旧形**：直接违反 ADR-0091 决策 5「不做双读」——那会让两套形状永久
  共存，以后每加一处读取都要记得处理旧形。
- **`find_knowledge_point` 默认 allow_partial**：出题侧带完整四元组时反而变松
  （同名跨年级会串），且把「猜」写进了默认路径。
- **用子串匹配知识点名**（「图形的运动」命中「图形的运动（轴对称）」）：这就是猜，
  与 ADR-0089「不猜图形」的立场冲突，且同前缀知识点很多时会错配。
- **让前端补 subject/grade 再提问**：用户不该为了看到图而改写自然语言；且这会把
  「上下文里有什么」变成用户的负担。

## 5. 守卫

| 测试 | 锁什么 |
|---|---|
| `tests/core/test_migrate_scene_specs.py::test_geometry_inside_inputs_is_migrated` | `inputs` 里的几何迁成新形 `figure`，`edges` 按顶点闭合，`inputs` 必须丢弃，产物过读路径校验 |
| `…::test_geometry_inside_inputs_uses_recorded_key_when_lookup_misses` | 反查落空时用 `inputs` 记的键（而非 `user_<hash>`） |
| `…::test_inputs_without_points_still_skipped` | 只有交互参数、没有顶点仍是「无几何」，跳过不臆造 |
| `tests/ai/subagents/tutor/test_scene_intent.py::test_l0_resolves_kp_when_subject_grade_missing` | 四元组缺 subject/grade 时仍放行到 L1 并出图 |
| `…::test_l0_partial_does_not_cross_teacher_or_name` | 放宽只放「缺字段」，不放归属与名字 |
| `…::test_l0_partial_prefers_row_with_scenes` | 同名多学期时优先取配了 scenes 的行 |
