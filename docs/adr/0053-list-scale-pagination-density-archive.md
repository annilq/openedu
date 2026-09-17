# 列表规模：分页 / 密度 / 归档

`题库` `任务` `错题本` 都会随时间单调增长，但三者「长在哪」完全不同，因此不能用同一套打法。
本 ADR 先登记实测现状，再对「取数 / 交互 / 密度 / 归档」四个方面分别决策。

## 背景：实测现状

| 模块 | 端点 | 接口分页 | 载荷 | 前端渲染 | 单卡高 | 一屏条数 |
|---|---|---|---|---|---|---|
| 题库 | `GET /questions` | ✅ `page/page_size/total`（offset+limit） | 每题含 answer/explanation | `SingleChildScrollView` + `Column`（非懒加载） | ≈95 | ≈8 |
| 任务 | `GET /tasks` | ❌ | **每 task 内嵌全部 questions**（`list_parent_tasks` 对每个 task 调 `get_task_questions`，N+1） | `ListView.separated`（懒） | ≈70 | ≈11 |
| 错题本（家长） | `GET /tasks/children/{id}/wrong-questions` | ❌ | 题干 + 答案 + 完整解析 | `SingleChildScrollView` + `for`（**非懒加载**） | ≈250 | ≈3.5 |
| 错题本（娃娃） | `GET /tasks/wrong-questions` | ❌ | 同上（不含答案） | `ListView.builder`（懒） | ≈150 | ≈6 |

单卡高为令牌算术估算（内容宽 1080、可视高约 900）：`bodyLarge` 15×1.5、`labelSmall` 12×1.35、
卡片内边距 `AppSpacing.md` 12、发丝边 1px。

三个已经存在、但还没被当问题的具体缺口：

1. **题库第 21 条之后的题，用户永远看不到。** 后端真分页，但
   `question_bank_notifier.load()` 固定传 `page: 1`、`pageSize` 取默认 20，且 UI 里没有任何
   翻页 / 加载更多控件——分页能力建好了没接上。
2. **任务页的载荷是 O(任务数 × 题数)。** 100 个任务 × 10 题 ≈ 1000 条带答案与解析的题卡，
   只为在列表上显示「10 题」。前端 `Resource<List<TaskModel>>` 全量持有后再客户端分三 Tab。
3. **家长错题卡的 `Text(item.stem)` 没有 `maxLines`。** 长题干能撑 5 行以上，卡片高度不可控；
   解析也全长展开。这是三个页面里密度最差的一个，且整页非懒加载。

共同缺口：没有「还有多少」的提示、没有稳定排序游标（三个列表都是新数据从顶部插入）、
家长端两个列表非懒加载。

## 决策

### 1. 取数：三端点统一信封 + 游标分页

- **统一 `PageResp<T>`：`items` / `total` / `next_cursor`。** `next_cursor == null` 表示到底。
- **排序键固定 `(created_at DESC, id DESC)`，游标取 keyset `(created_at, id) < (…)`，不用 offset。**
  理由：三个列表都是「新数据从顶部插入」，offset 分页在两次请求之间插入新行时会重复或漏掉一条
  （页面上表现为「这道题出现了两次」）。`page_size` 默认 20、上限 100（沿用 `/questions` 现取值），
  `page` 参数保留但标记 deprecated；AI 查询工具仍走 `limit` 一次性取数，不动。
- **任务列表不再内嵌 questions。** 新增 `TaskSummaryResp`（`question_count` + `subjects` 摘要 +
  `status` / `created_at` / `child_id`），完整题只在 `GET /tasks/{id}` 返回。列表响应额外带
  `counts: {draft, ready, assigned, done}` 供三个 Tab 徽标——否则徽标数字仍需全量拉取，
  分页就白做了。
- **错题加 `only_active: bool = true`**（配合 §4），家长端与娃娃端两个端点共用同一 service 分页分支。
- **`total` 改 `SELECT COUNT(*)`。** 现在 `list_bank_questions` 用
  `len(session.exec(stmt).all())`——把全部行读进内存只为数个数，分页省下的 IO 又赔在计数上。
- **补复合索引**：`Question(parent_id, created_at DESC)`、`Task(parent_id, created_at DESC)`、
  `WrongQuestion(child_id, first_wrong_at DESC)`（`child_id` 现有单列索引不够覆盖排序）。

### 2. 交互：统一「追加式加载」，不按设备形态分叉

- **三个页面统一：首屏 20 条 → 触底自动追加 → 底部常驻「加载更多」按钮。**
  按钮不是装饰：触底自动加载对键盘 / 读屏用户不可达，显式按钮是可达性与失败兜底。
- **不做页码器。** 三个页面的定位职能已经由筛选器承担（学科 / 年级 / 状态 / 关键词 / 时间），
  「跳到第 7 页」与这个心智重复；页码按钮在触屏上还踩 44 触控目标的下沿。
- **追加必须给终点感**：底部显示「还有 N 条」（`total - loaded`），到底后换成发丝线 + 「已全部加载」。
  否则无限滚动没有终止反馈，用户不知道该不该继续滑。
- **桌面（可用宽 ≥ `AppLayout.largeMin` 1200）靠 detail 栏提效，不靠更密的列表。**
  点击行在右栏展开详情（ADR-0045 的 `masterFlex`/`detailFlex`），列表滚动位置不丢、不用来回进出。
  家长端题库与错题本现在是 `SingleChildScrollView` 整页，改造时把列表抽成 master、选中项进 detail。
- **设备形态判定禁令同 ADR-0045**：列数与加载形态只看 `LayoutBuilder.constraints.maxWidth`，
  禁止 `MediaQuery.size` / `orientationOf` / 平台判断。

### 3. 密度：先加列、再截断内容，间距最后动

- **卡片内边距保持 `AppSpacing.md` 12 不动。** 题库行 95、任务卡 70 都在触控目标 44 之上；
  把 `md` 降到 `sm` 只省 8px（<10%），却会打破「卡片内边距 = md」这条全站约定。
  **间距不是这三个页面的瓶颈，内容才是**——这是对原问题「是否应该调整间距留白」的直接回答。
- **行间距统一到 `AppSpacing.sm` 8。** 现在三种值：题库 8（`margin bottom: sm`）、
  任务 12（`separator: md`）、错题 16（`margin vertical: sm`）。行卡自带 hairline 描边，
  8 足够分隔；统一后错题本每行省 8px。
- **页面外边距统一**：左右 `AppSpacing.lg` 16、顶 `AppSpacing.lg` 16、底 `AppSpacing.xl2` 28。
  现在顶部三种值（12 / 16 / 12）。
- **列表正文一律 `maxLines: 2`。** 家长错题卡目前无截断，这是单卡高度不可控的直接原因。
- **家长错题卡：答案保留一行，解析折叠。** 解析默认收起，展开控件走 `AppIconAction`
  （禁止 `CupertinoButton(padding: zero)`，见 ADR-0044）。单卡 ≈250 → ≈150。
- **内容宽 ≥ 1048 时列表走 2 列网格。** 列宽锚 `AppLayout.contentCard` 520：
  用 `maxCrossAxisExtent = contentCard`，由 `maxWidth` 决定实际列数（1080 → 2 列；
  700 中屏 → 1 列；大屏 detail 打开时 master 约 446 → 1 列）。**上限 2 列**：3 列会把列宽压到
  352，低于 `contentNarrow` 480 的可读下限。列间距 `AppSpacing.md` 12——比行间距大一档，
  因为列与列之间没有描边分隔。
- 责任边界同 ADR-0045：`AdaptiveShell` 只给宽度，列数由页面自己按 `maxWidth` 算。

### 4. 归档：三个模块是三件事，不做成一个功能

| 模块 | 增长源 | 「不用再看到」的判据 | 机制 |
|---|---|---|---|
| 题库 | 每次出题都沉淀 | 家长判断「这题不想再用了」 | **显式归档** + 可恢复 |
| 任务 | 每次布置都产生 | 已完成 + 时间久远 | **不加字段**：按月分段折叠 |
| 错题 | 答错即入集 | 复习阶段走完 = 已掌握 | **自动归档**：毕业不再物理删除 |

- **题库：显式归档。** `Question` 加 `archived_at: datetime | None`（可空 = 未归档，
  复用现有迁移回填手法）。默认过滤掉已归档；顶部加「只看在用 / 含已归档 / 只看已归档」
  三态切换（走 `AppSelectStrip`，缺省「只看在用」）；批量归档并入已有的「选中 N 题」操作区。
  动机：现在被任务引用的题**删不掉**，家长于是「不敢删、只能堆着」——归档正是为这个心理设计的，
  它必须是可恢复的。
- **任务：不加归档字段。** `done` 已是终态，再加 `archived` 会造出「done 但未归档 /
  已归档但非 done」两种重叠状态，而且没人能回答「什么时候该点归档」。改为：已完成 Tab
  按月份分段（`SectionTitle` 风格的小标题），默认展开最近 3 个月，更早折叠为
  「2026 年 6 月及以前（42）」。分段边界由前端按已加载数据算，不新增接口。
- **错题：把「毕业即物理删除」改成「毕业即归档」。** 现状 `apply_review_outcome` 在末位阶段
  答对时 `session.delete(wq)`。错题本不膨胀是好的，但代价有二：(a) 学习痕迹永久丢失，
  「这题错过 5 次、现在掌握了」再也查不到；(b) `mastery` 的 `active_wrong` 与
  `max_review_stage` 只统计活跃错题，物理删除会让掌握度掉档。改为加
  `WrongQuestion.graduated_at: datetime | None`：末位阶段答对时打时间戳而非删除；
  默认 `only_active=true` 过滤；家长端错题本加「已掌握（N）」分区，只读、可
  「重新加入复习」（清 `graduated_at`、stage 归 0、`due_at = now`）。
- **顺带回答「错题本会不会无限长」**：会长的只有「从不复习」的错题（`review_stage` 恒为 0、
  永远不毕业），那是待复习队列到达率的问题，归档救不了，不在本 ADR 范围。

### 5. 不做的事

- 不引入第三方分页 / 无限滚动库：`ListView.builder` 已是懒加载，够用。
- 不做虚拟滚动之外的自绘列表。
- 不做「一次拉全部 + 前端过滤」：任务页现在是这个形态，数据量上来会先卡网络再卡内存。

## Considered Options

1. **只加密度不动接口**：能推迟问题，但题库第 21 条至今不可见，且任务页载荷是
   O(任务数 × 题数)——加密度对这两条都无效。拒绝。
2. **只加 offset 分页**：改动最小，但新题 / 新任务从顶部插入时页界漂移，
   且 `total` 现在靠 `len(全表)` 计算，省下的 IO 又赔在计数上。拒绝。
3. **全站页码器**：精确可深链，但页码按钮在触屏上踩 44 触控目标下沿，
   且与「筛选器定位」的现有心智重复。拒绝。
4. **三个模块共用一套 `archived` 字段**：同名但三义（家长主动弃用 / 时间久远 / 系统判定已掌握），
   共用一个字段会让「这行为什么被归档了」无法回答。拒绝。
5. **游标分页 + 追加式加载 + 密度三档 + 语义分离的归档**（采用）。

## 守卫

- `frontend/test/list_pagination_test.dart`（新）：追加后 `items.length` 累计正确、
  `hasMore` 随 `next_cursor` 翻转；触底回调防抖只触发一次；`next_cursor == null` 后不再发请求。
- `frontend/test/wrong_question_card_test.dart`（新）：家长错题卡 stem 最多 2 行；
  解析默认不渲染，点展开后出现。
- `frontend/test/list_density_test.dart`（新）：`maxWidth` 1080 → 2 列；700 与 446 → 1 列；
  列间距 = `AppSpacing.md`。
- `backend/tests/`（新）：两次翻页之间插入一条新数据时不重不漏；`GET /tasks` 列表项
  `questions` 为空且 `question_count` 正确；`counts` 与实际一致；归档过滤默认生效；
  错题毕业写 `graduated_at` 而非删除。
- `frontend/test/task_review_detail_fetch_test.dart`（新）：把「列表摘要」当入参渲染审核页，
  页面必须补取一次 `GET /tasks/{id}` 并渲染出题目（修复前该测试红灯：不取数 → 空态）；
  同一位置换 taskId 必须重新取数（provider 以 id 为 key，不重取会永远停在加载态）。
- 既有守卫不得回归：`adaptive_shell_layout_test.dart`、`app_focusable_keyboard_test.dart`
  ——新增的「加载更多」按钮与归档切换必须走 `AppFocusableAction`，裸 `GestureDetector` 是 bug。

## 后果

- 题库终于能翻到第 21 条；任务页载荷从 O(任务×题) 降到 O(任务)；家长错题本单卡高度减半并改懒加载。
- 「还有 N 条」与「已全部加载」让长列表有终点；detail 栏让桌面端不必靠加密列表提效。
- 归档按语义分成三套，代价是三处实现、三套文案；换来的是每行数据的归档原因都可解释。
- 错题毕业从「删除」改「归档」是行为变更：已有的毕业错题不会回溯（历史删除无法恢复），
  需在下一次迁移说明里写明。
- 已知代价：游标分页不可跳页，「直接翻到很靠后的位置」只能靠筛选器缩小范围。

## 实施顺序

- **P0（数据不可见 / 载荷爆炸）**：任务列表拆 `TaskSummaryResp` + `counts`；三个端点统一
  `PageResp` + 游标；题库前端接上翻页；家长错题本 `SingleChildScrollView` → `ListView.builder`。
- **P1（密度）**：错题卡 `maxLines: 2` + 解析折叠；行间距 / 外边距统一；2 列网格。
- **P2（归档）**：题库 `archived_at` + 三态切换；任务按月分段；错题 `graduated_at` 替换物理删除。

## 实施状态

| 阶段 | 状态 | 说明 |
|---|---|---|
| P0 分页 | ✅ 已落地 | `core/pagination.py` 游标原语；`GET /questions` `/tasks` 两个错题端点统一信封；任务改 `TaskSummaryResp` + 服务端 `counts`；前端收口 `CursorPage<T>` / `PagingState<T>`。 |
| P1 密度 | ✅ 已落地 | 题干 2 行 / 答案 1 行 / 解析默认折叠（`AppTextAction` 展开）；可用宽 ≥ 1048 时两列（`AppCardSliver`）；行距与页边距收口成 `AppLayout.listRowGap` / `listColumnGap` / `listGutter`。 |
| P2 归档 | ✅ 已落地 | 题库 `archived_at`（显式、可逆）；任务按月分段（不加字段）；错题毕业改打 `graduated_at` 软删除 + 家长端「已掌握」分区与重新加入复习。 |

与本文的偏差（落地时发现的，按实际情况登记）：

- **`PageResp` 没有做成统一类型名**，而是 `CursorPage<T>`（Dart 泛型）+ 各端点的具体
  响应类继承/特化它（`TaskPage` 带 `counts`、`WrongQuestionPage` 带 `graduated_total`）。
  原因：分页之外还要带「这一页额外的东西」，统一成扁平信封会逼着每个端点都去读
  `extra` 字典。
- **2 列不用 `SliverGrid`**：行高由 `childAspectRatio` 钉死，而卡片高度随题干行数与
  解析是否展开变化，钉死会裁内容。改成分行 `Row` + `Expanded`，行高取该行最高卡。
- **任务按月分段的分段边界由前端按已加载的页算**，未新增接口：分页之后「更早」
  本来就随追加变长，服务端分段要额外传参且收益相同。
- 迁移一律走启动期偏幂等 DDL（`CREATE INDEX IF NOT EXISTS` / SQLite `PRAGMA table_info`
  查列后 `ADD COLUMN` / Postgres `ADD COLUMN IF NOT EXISTS`），不引入 alembic。
- **列表摘要不得被当作完整任务消费**（P0 落地后发现，属本条 ADR 引入的回归）：
  `GET /tasks` 不再内嵌题目后，家长从任务列表 / 概览点进「草稿审核」页时手里那份
  `TaskModel` 的 `questions` 恒为空，而审核页当时是**拿它当初始 state** 的（从不调用
  `load()`），于是渲染出「草稿暂未包含任何题目」——题一直在 `task_question` 表里，
  列表卡片上的「N 题」也是每次请求对同一张表现算的（`task_question_breakdown`），
  两者不可能不同步；断的是「详情页没去取」。
  定下的契约：**详情 / 审核页一律自己回后端取一次完整任务，入参只当「要打开哪条」的信封**。
  实现上 `ReviewNotifier` 删掉了 `initial` 参数（起始态恒 `ReviewLoading`，让「进页面必须
  取数」成为类型上绕不过的事），`parentTaskReviewProvider` 的 family key 从 `TaskModel`
  改成 `taskId`（该类没有覆写 `==`，拿 identity 相等当缓存键迟早造出第二个 notifier）。
  副作用：从生成流进入审核页会多一次 `GET /tasks/{id}`——换取「页面上看到的题目一定来自
  服务端」。
