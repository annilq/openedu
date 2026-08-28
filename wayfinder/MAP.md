# 地图 · 娃娃兴趣画像 + 个性化出题

> 标签：`wayfinder:map`
> 创建：2026-08-28 ｜ 方式：/wayfinder（规划，不直接落地实现）
> 配套基线：`wayfinder/分析_领域与业务关系.md`

## Destination

在家庭私用学习闭环中，为娃娃建立**兴趣画像**（受控多选分类 + 自由补充），并在 AI 出题管线中**默认轻量融入兴趣作情境**、提供显式**「按兴趣出题」模式**；兴趣仅作口味、绝不绕过内容安全与 curriculum；画像数据落在 `User.interests` JSON 列。本地图收口为一份**路线清晰、决策已决的可执行实施方案**（设计/规格层），实现作为地图清晰后的交接。

## Notes

- 已确认范围（用户拍板）：①画像中心（兴趣 + 可选学习习惯字段）②受控多选 + 自由补充 ③默认轻融入 + 兴趣题模式 ④`User` 表加 JSON 列 `interests`。
- 兴趣是**出题意境调味剂，不是 curriculum 锚点**（锚点 = `knowledge_point`）；绝不绕过 `_SYSTEM` 年龄锁与学科白名单。
- 关键接缝：`langchain_provider.generate_question` 的 prompt 模板、`UserCreate`/`User` schema、`AddChildScreen` → `POST /children`、`init_db`（`create_all`，无 Alembic）。
- 每会话至多收口一票（研究票除外，可并行）。HITL 票须经用户拍板。
- 参考：`backend/app/domain/provider.py`、`langchain_provider.py`、`mock_provider.py`、`app/models.py`、`app/api/routes/children.py`、`tasks.py`、`frontend/lib/features/children/**`。

## Decisions so far

<!-- 索引：每条已决票一行 gist + 链接；细节只在票内 -->

- [兴趣分类词表（内置分类 + 自由补充）](tickets/01-兴趣分类词表.md) — ✅ HITL 已收口：两级（15 一级 + 可选二级），自由文本 50 字内参与出题；取值约束写回 WF-2/WF-3/WF-5。
- [「按兴趣出题」模式交互](tickets/04-兴趣题模式交互.md) — ✅ HITL 已收口：家长出题表单叠加「按兴趣出题」开关 + WF-1 词表点选 + 多选主题均分；**修正 WF-3 的 `focus_interest` 为 `list[str]`**，并扩展 WF-2 在 `Task` 加 `focus_interest`。
- [出题管线兴趣注入（mock + langchain + batch）](tickets/03-出题管线兴趣注入.md) — 研究票已收口（**待实现时按 WF-4 修正**：`focus_interest` 由 `str|None` 改 `list[str]|None`，多主题轮询均分）。
- [前端兴趣采集 UI（创建 + 编辑共用一页）](tickets/05-前端采集UI.md) — ✅ HITL 已收口：统一 `ChildFormScreen`（create/edit），`InterestPicker`（WF-1 一级+二级）+ 单 50 字「其他爱好」；`UserModel.interests: InterestsModel`；**依赖后端新增 `PUT /children/{id}`**（当前仅 POST/GET）。
- [数据建模与无 Alembic 迁移方案](tickets/02-数据建模与迁移.md) — 研究票已收口（**按 WF-1/WF-5 修正**：`User.interests` 形状 = `{"categories": list[str], "free_text": str|null}` 叶子 key + 单自由文本）+ **（按 WF-4 扩展）`Task.focus_interest: list[str]|None`**；schema 改动清单 + `create_all` 加列与旧 child 回填。

## Not yet specified（迷雾，朝向目的地）

- 复习调度（F-202 遗忘曲线）与错题归集（F-201）再次生成的题，是否也融入兴趣？
- 兴趣是否参与「从题库建任务」（from-bank / 题库复用闭环）的选题？
- 自由文本兴趣的归一/去重/长度上限细则（与安全护栏票 WF-6 相关）。

## Out of scope（超出目的地，本努力不展开）

- 兴趣 × 薄弱点交叉洞察看板（家长端新维度）——未来增强，不在本期。
- 兴趣标注题库（`Question` 层打兴趣标签供检索）——超出本期范围。
- 多娃娃兴趣对比 / 社交化兴趣发现——不在家庭私用闭环内。
- 答疑个性化若被 WF-7 判定为本期范围，则移出此处。

## Implementation（2026-08-28 已落地并验证）

WF-1 ~ WF-5 全部实现；WF-6（安全护栏措辞）、WF-7（答疑个性化）仍为开放前沿票，未纳入本次实现。

### 后端
- `app/models.py`：`UserBase.interests`（JSON）、`UserUpdate`（display_name/grade/interests 均可空）、`TaskBase.focus_interest`（`list[str]` JSON）、`TaskBatchCreate.focus_interest`。
- `app/crud.py`：`batch_generate_task(..., focus_interest)` 落库；新增 `update_user()` 局部更新（忽略 None）。
- `app/api/routes/children.py`：新增 `PUT /children/{id}`（校验 `parent_id` 归属 + `role == "child"`，否则 404/400）——补上 WF-5 依赖的缺口。
- `app/api/routes/tasks.py`：`_extract_interests_pool(child)` 抽兴趣池（categories + free_text）；`_generate_task_questions_for_specs(specs, interests, focus_interests)` 按题轮询 `focus_interests[i % n]`，**聚焦态不再叠加轻融入**（避免双模式叠加）；`batch_generate` / `regenerate_all` / `regenerate_one` 三处复用同一逻辑。
- `app/domain/*`：`LLMProvider.generate_question` 增加 `interests` / `focus_interest`；mock 打标 `（兴趣：X）` 与 `（兴趣池：…）`；langchain 双模式 prompt（聚焦=「围绕主题 X 讲清知识点」，轻融入=「可结合兴趣作情境包装」），`_SYSTEM` 年龄锁未动。
- `app/core/db.py`：`run_migrations` 补 `user.interests` 与 `task.focus_interest` 两列（sqlite `TEXT` / postgres `JSON`，带列存在性检查，幂等）。

### 前端
- `models.dart`：新增 `InterestsModel`（categories/freeText/isEmpty）；`UserModel.interests`；`TaskModel.focusInterest`。（注：`TaskSpecModel` **不加**兴趣字段——兴趣主题是任务级而非规格级，与后端 `TaskBatchCreate.focus_interest` 顶层字段对齐。）
- 数据层：`createChild(interests)` + 新增 `updateChild(...)`，贯通 data source / repository / notifier 三层。
- UI：新增 `InterestPicker`（WF-1 词表两级多选 + 50 字「其他爱好」自由文本）、`ChildFormScreen`（create/edit 共用；编辑态锁定账号与密码）、`_ThemeToggle` 兴趣主题芯片。
- 入口：`home_screen` 的 nav 5 与侧栏铅笔图标均接 `ChildFormScreen(edit)`；`parent_task_form_view` 增加「按兴趣出题」开关 + 主题点选（题量在所选主题间轮询均分）；`parent_sidebar` / `parent_child_selector` 透传 `onNavigateToEditChild`。
- 删除 `add_child_screen.dart`（由 `ChildFormScreen` 取代）。

### 验证结果
- 后端 `uv run pytest`：104 passed, 1 skipped。
- 前端 `flutter analyze`：**No issues found**；`flutter test`：**31/31 passed**。
- 功能冒烟：兴趣池抽取 = `categories + free_text`（无兴趣时 `None`）；聚焦模式 2 主题 × 4 题轮询为 `恐龙/太空/恐龙/太空`，3 主题为 `恐龙/太空/足球/恐龙`；关闭开关回落轻融入 `（兴趣池：…）`。

### 实现期踩坑（供后续参考）
- `LucideIcons` 并非来自 `lucide_flutter`，而是由 **`shadcn_ui` 再导出**；未导入 `shadcn_ui` 的文件直接用 `LucideIcons` 会报 undefined。
- `AppTextField` 的 label 是 `ShadInput` 的**兄弟** `Text`，且输入框是 `ShadInput`（内部 `EditableText`）而非 Flutter `TextField`——测试里 `find.widgetWithText(TextField, label)` 匹配 0；应改用「含该 label 的 `AppTextField`」作为 `enterText` 目标。
- 含 shadcn 组件（`ShadButton`）的 widget 测试需 `ShadApp` 祖先提供 `ShadTheme`；因 `ShadApp` 基于 `WidgetsApp` 而非 `MaterialApp`，用 `ShadApp.custom(appBuilder: (ctx) => MaterialApp(...))` 可同时满足 ShadTheme 与 Material。
- 表单变长后提交按钮落到视口外，测试需先滚动；树中多个 `Scrollable` 时必须显式传 `scrollable: find.byType(Scrollable).first`，否则 `scrollUntilVisible` 报 "Too many elements"。

## 票清单（决策票）

| 票 | 类型 | 状态 | 阻塞 |
|---|---|---|---|
| [WF-1 兴趣分类词表](tickets/01-兴趣分类词表.md) | prototype (HITL) | ✅ 已收口 + 已实现 | — |
| [WF-2 数据建模与迁移](tickets/02-数据建模与迁移.md) | research (AFK) | ✅ 已收口 + 已实现 | — |
| [WF-3 出题管线注入](tickets/03-出题管线兴趣注入.md) | research (AFK) | ✅ 已收口 + 已实现 | — |
| [WF-4 「按兴趣出题」模式交互](tickets/04-兴趣题模式交互.md) | prototype (HITL) | ✅ 已收口 + 已实现 | WF-1, WF-3 |
| [WF-5 前端兴趣采集 UI](tickets/05-前端采集UI.md) | prototype (HITL) | ✅ 已收口 + 已实现 | WF-1, WF-2 |
| [WF-6 兴趣注入安全护栏措辞](tickets/06-安全护栏措辞.md) | grilling (HITL) | 开放·前沿 | — |
| [WF-7 AI 答疑是否同步个性化](tickets/07-答疑个性化范围.md) | grilling (HITL) | 开放·前沿 | — |
