# 资料库 / 知识点多选删除与「删除资料的知识点连带口径」

## 背景

两项诉求：

1. 资料库只能逐份删资料，没有多选批量删除；
2. 知识点管理有勾选（用于「确认转正」）但没有删除入口——涌现出的知识点错了或不想要，家长无处可删。

顺带必须回答一个设计问题：**删除资料时能不能自动删掉资料关联的知识点？**

### 为什么「连带删除」不是天然成立

`KnowledgePoint` 与 `Material` 之间**没有外键**：一份资料把知识点名字存在
`Material.knowledge_points`（JSON 字符串数组），另一端 `KnowledgePoint` 按
`(parent_id, subject, grade, semester, name)` 唯一。链接只有**名字**。由此三条后果：

1. **同名共享**：提取走 `upsert_pending_knowledge_point`——两份资料抽出同一个「两位数乘法」，
   目录里只有一行。删掉其中一份资料，知识点仍有另一个来源，不能删。
2. **学期是独立第四维**：「位置与方向」在上/下学期各一行（各自配讲解模板），上层资料只应
   带走它自己那一学期那一行。
3. **确认即接管**：`pending` 是「AI 给的候选」，家长点「确认选中」→ `curated` 意味着**认可**，
   还可能在「讲解」里配好了 `scenes` 模板。那是家长的劳动成果，不能被删资料顺手抹掉。

结论：**能删，但只能删「孤儿」**——没有别的来源、且从未被家长接管的待审涌现点。

## 决策

### 后端

- **`POST /materials/bulk-delete`**（`MaterialDelete{ids, cascade_knowledge_points}`）：
  去重后逐个 `require_owned`，删资料 + 片段 + 落盘文件；返回
  `{deleted, deleted_count, chunks_removed, knowledge_points_removed}`。
  单个 `DELETE /materials/{id}` 语义不变（**默认不级联**），保持「删什么就是什么」。
- **`POST /materials/knowledge-points/bulk-delete`**（`KnowledgePointDelete{ids}`）：
  按 `parent_id` 过滤后删行，越权 / 不存在 id 静默跳过、`deleted_count` 不谎报。
- **孤儿判定**收口在 `repository.prunable_knowledge_points`，三条口径缺一不可：
  ① 同 `(subject, grade, semester, name)` 才定位；② **其它留存资料的知识清单里没有这个名字**
  （跨学期也算；被删的这批自己要排除，否则两同批资料互相「担保」就一个也删不掉）；
  ③ 只删 `source=emerged` 且 `status=pending`。
- 学期口径必须与提取时（`_extract_and_align`）逐字一致：显式学期 > 文件名推断（上册/下册）>
  `上学期`。差一个字就定位不到当初涌现的那一行，级联会静默失效。

### 前端

- 资料列表加多选态：组合既有 `AppSelectStrip`（全站统一的「多选 / 已选 N / 全选」语言），
  「删除选中」走全站破坏动作语言 `AppTextAction(color: error)`；
  **删除前必确认**，且必须说明连带效果（会清理哪些、不会动哪些）。
- 勾选状态放在 `MaterialLibraryState`（`selecting` + `selectedMaterialIds`），而不是 widget 局部态：
  provider 在每次 `load` 后按可见资料裁剪勾选，避免「看不见却被选中」导致误删。
- 删除失败**不清勾选**：家长可直接重试或改选。
- 知识点管理的「删除选中」与「确认选中」**共用同一份勾选**；`deletableSelectedCount` 只数已落库
  （有 id）的行——骨架条目在 DB 里还不存在，按钮计数必须用这个数，否则会出现「删除选中（3）」
  而实际只删 1 条。
- 新增共享 `AppCheckbox`（`AppFocusableAction` 内核，保证 Tab / Enter 可达），替换知识点管理里
  的私有 `_checkBox`；多选条单独成文件 `material_library_select_bar.dart` 以守住 ADR-0058 的
  400 行上限。

## 接受的代价

- **批量删除不是单事务**：资料逐个删并提交，中途失败会留下部分已删状态。可接受——每个删除本身
  都合法，且 `require_owned` 前置保证了越权在删之前就被拦下。
- **「不想连知识点一起删」没有开关**：只删好提交的那一组（最有代表性的是「刚传错」），
  而已转正的点在哪都被保留；真要精细控制，去「知识点管理」删即可——那里现在有了删除能力。
- **`still_used` 只看 `(学科, 年级, 名字)`，不看学期**：宁可保守不删（跨学期同名即使不在同一学期
  也不删）。漏删比误删便宜——漏删家长还能手动删，误删不可逆。

## Considered Options

- **删资料时无条件删掉它的知识点**——否。同名共享会让另一份资料的知识点凭空消失，且会抹掉家长
  确认过、配好讲解模板的行。
- **给父表加 `material_id` 外键做真级联**——否。知识点 deliberately 是多对多概念目录（`upsert`
  去重），要支持多份资料共享同一个点；加外键就得改成「每资料一份知识点」，与本模型冲突。
- **多选删除套 assistant 的「延迟删除 + 撤销」**——否（资料删除涉外网盘文件与向量，
  延迟执行的中间态更复杂；这里用显式确认弹窗即可，语义更直白）。
