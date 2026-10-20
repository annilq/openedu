# openedu · 项目长期约定
> 权威源 `.impeccable.md`/`docs/adr/`/`docs/agents/*.md`；术语 `CONTEXT.md`；入口 `AGENTS.md`。只留实测数字/归因/操作纪律。

## 0. 环境/命令
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）；`flutter test`/`analyze` 须 `no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同`（WS 升级失败）；`flutter analyze` 退出码非0→认 `No issues found!`。
- 禁 `dart format`（本机 tall style 噪声）；新增原生插件须完整重跑 App（Hot Restart 不补原生注册→pigeon channel-error）。并行 worktree：`git worktree add /tmp/oedu-tXX -b ticket/XX <base>`+软链 `backend/.venv`/`.env`；worktree 下 pytest 须 `PYTHONPATH=/private/tmp/oedu-tXX/backend`。
- **后端全量 pytest 必带 `--basetemp=/tmp/<新目录>`**（主仓同样）：默认 `/private/var/folders/.../pytest-of-root` 的 mkdir 被沙箱拒 → 几十条 setup ERROR（courseware/migration 一批文件），极易误判成自己写的回归；单文件跑不受影响。跑完记得 `mv .env.hidden .env` 还原。

## 1. 前端分层
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`（写意图 `guide`(20)>只读 `query`(12)）。结构化键=manifest `actions`(ADR-0081)：`task_generate`/`quiz_generate`/`courseware_hint`/`quiz_judge`。出题=`POST /tasks/generate`(流式)+`/tasks/from-generated`(重生成全删)。单向 `main/→features/*→shared/*`；R4：`presentation/` 禁 import `*/data/`(测试 `feature_boundaries_test.dart`)。
- **出题触发词缺口（2026-10-19 实测）**：`出道` 是触发词但 `出一道` 不含它（子串不覆盖）；`出一道/来一道/出一题` 规则与启发式全落空 → 兜底给 tutor（`hints=[]`、`priority=-10`，manifest 注释明示此设计），出题请求被当文本问答（DB 实证 routing=伴学答疑、tool=tutor_explain、0 张题卡落库）。main 与 ADR-0098 合并版同缺；`6489a97` 串台修复未覆盖。修法：词加进合并版出题段 + `intent_schemas.generate` + 真实 classify 契约测试。
- **流式题卡无 `scene_spec` 生产者**：前端 `AssistantQuestionCard` 已渲染 `scene_spec`、`QuestionPreview` 已透传、落库 `tasks/service.py:616-633` 优先用前端回传的「出题时已算好的」——但 `GeneratedQuestion` 无此字段、`generate_questions` 不构建 → 聊天题卡永远无图（只有落库后的任务/题库页读 `scene_spec_for_read`）。tutor 侧另有 `interactive_scene` 卡（`scene_intent.py` L0/L1/L2 三层，模型判定 + 同键去重），与出题侧互不复用。聊天题卡 options 走 `cardStr`（`{text,figure_key}` dict 会渲染成 map 字符串），`QuizOption.parseList` 只在 `QuestionPreview` 用——形状不一致（潜伏）。

## 2. 视觉/控件（analyze 照不出）
- 禁用 Material 控件(`InkWell`/`Icons.`/`Scaffold`/`ListTile`/`Divider`/`Tooltip`)：根 `ShadApp`+`CupertinoApp` 无 Material 祖先→抛「No Material widget found」。可点区一律 `AppFocusableAction`。
- `ShadButton.height` 内容盒高+描边画盒外→可见高=值+2×描边宽(声明32实测40)；并排按钮 `Wrap`。`ShadCard` 高于内容→调用点自包 `Center`。`Row(stretch)` 须包 `IntrinsicHeight`（裸必崩；**子树含 `LayoutBuilder` 也崩**）；`Column(stretch)` 安全。色条=`Stack`+左 `Container`+卡片 clip 裁圆角（非均匀 Border 喂 ShadCard 抛 `borders with uniform colors`）。白物体纸底 `#FDFBF7`→补描边。

## 3. 自适应/布局(ADR-0045/0059)
- `AdaptiveShell`：紧凑<700=娃娃底栏/家长抽屉；≥700=侧栏240↔64。导航单一：`sealed ParentPage`/`TeacherPage` 只调 `_go(page)`。文件规模棘轮(ADR-0058)：`test/file_size_guard_test.dart` `_baseline` 只许下调，新文件>400行直拦；搬代码禁正则删方法(逐行搬)。内容兜底 `Align(topCenter)`+`ConstrainedBox`(非 `Center`)。push 整页 `AppContentFrame`+`AppPushedPage`(`showBack`默认true)。

## 4. 测试/截图
- `ShadApp.custom(appBuilder:)` 不装 `ShadToaster`→widget 测试须显式 `ShadToaster(child:)`。禁 `test/` 写截图装置（`RenderRepaintBoundary.toImage()` 无合成器永不完成→改几何断言）。网络层加接口须同步 4 测试替身(`assistant_api_client_test`/`list_archive_test`/`review_notifier_test`/`students_notifier_test`)。长按 `startGesture`+`pump(kLongPressTimeout)`；子串匹配词边界锚定防护栏误报。

## 5. Git/后端
- 提交按逻辑批次拆、`chore(memory):` 单独提交；`git commit -- <file>` 重暂存整个工作区→`git add -p` 后不带 pathspec `git commit`。平台目录不在版本控制→补丁脚本幂等+`--check`。
- 引擎失败：`decrypt()` 解不开只返 None；`ToolUnsupportedError` vs `ProviderRequestError(kind+user_hint)`（`genkit.py#classify_failure`）；禁 `except Exception`。可空 JSON 列须 `JSON(none_as_null=True)`(ADR-0061)；SQLite「加列」≠「加约束」→改 UNIQUE 须重建表。选项标号只渲染层画+剥前缀：`cleanOptionText`(ADR-0061 §T)。
- pytest 前 `cd backend && mv .env .env.hidden`；`.venv/bin/pytest` ~25s；真库 `backend/app.db`→必先 `cd backend`。长列表(ADR-0053)：keyset 游标；读错题加 `graduated_at IS NULL`。分层不变量9：归属只许 `core.guard`(`require_owned`/`find_owned`/`require_owned_child`/会话三件套)，禁内联；AST 守卫 `tests/ai/test_layering_invariants.py`（只认 `!=`/`is not` 比较，SQL 里的 `==` 过滤不算违规）；改 `features/*/service.py` 必跑 `tests/ai/`。同一实体两份 schema：`features/*/service.py`(助手投影)与 `router.py`+`schemas.py`(REST)；前端打 REST。`scene_spec_for_read`(ADR-0061 §U) 唯一交互讲解读路径。

## 6. 题型/班级/ADR 状态
- 题型(ADR-0004 D5)：qtype `{choice,fill,calc,open}`；选择题≥2 选项(`TASK_CHOICE_NO_OPTIONS(422)`)；多选 `multi:bool` 仅 `choice`。判断题=`choice`+对/错(`isJudgeQuestion`)；`Conversation.pending_quiz` 已删(ADR-0090)，`chat()` 直接 `IntentSignal`；tutor `_read_history`→`_question_card_text`。
- 班级管理(ADR-0068+0086)：后端 `Class`(`teacher_id,name,grade(1–9)`)+`User.class_id`；`/classes` CRUD+`/students?class_id=&keyword=`+导入导出；`POST /students`/`/students/import` 增 `class_id`；前端缺 `features/classes/presentation/`；ADR-0086 补「班级管理」(`TeacherPage.classManagement`)；年级由 `Class.grade` 承载，`user.grade` 全删。
- **ADR 状态：0088/0089/0090/0091 全 done**（集成分支 `integration/adr-0088-0091`）。0091=`SceneSpec` 直接持 `Figure`、几何归一、前端 `FigureShape` 补 `edges`；0089-04=前端选项内联图形(`QuizOption{text,figure?}`+`AppOptionTile` 行内缩略图+`ReflectionSceneDialog`，`flutter test` 543 passed)；0090=判断题闭环子代理化+修三前端既存红；0088=角色枚举+admin+运行轨迹页+脱敏破窗。详见 `docs/adr/`。两份 ADR 状态已由「草案」改「已实现」(commit `2db8e58`)；工单在本地 `.scratch/scene-spec-figure-unification/`(6 票)+`scene-aware-ai-loop/`(4 票)，gh 未登录故未转 GitHub issue。

## 6b. 会话归属 = 本人可见（ADR-0096，取代 ADR-0048 §3/§6）
- 判据唯一真源 `core.guard.conversation_owner_clause(user)`：学生 `student_id==me`；教师/admin `teacher_id==me AND student_id IS NULL`（教师**看不**到学生的）。三消费者同源：`list_my_conversations`(SQL 过滤)/`require_owned_conversation`(详情断言)/`owned_conversation_ids`(删除批量)——分家必出「列表能列出、详情 403」。
- **`Conversation.teacher_id` ≠ 归属**：它表示教学域（RAG 范围、`resolve_engine`；学生端 None→资料库回落 mock），学生的会话也填其教师。故不加 `owner_user_id` 列（会与 teacher_id 并列重新混淆 + 迁移双写成本）。
- 会话三端点 `CallerDep` 双端通用（学生端有自己的列表）；响应无 `student_id`/`student_name`；前端**无只读态**（`_AssistantMode.reading` 已删），列表单段、每条可续接。历史学生会话留库不删（可逆）。审计仍走 `/ai/debug/conversations`(`require_owned_or_admin`)，是另一个消费者。
- 教师失去「看学生在问什么」→ 该需求归 F-305（粒度=交换），不在会话列表另造入口。

## 7. ai-prompts-hardening epic（已合入 main 并删除分支）
- 3 票：01 capability(ADR-0079)+02 知识点聚焦(ADR-0080) 已 done（commit `ec67a75`+`4e3eeff`，隔离 worktree `/tmp/oedu-aph`）。纪律：开发在隔离 worktree、零污染主树。
- 03(b) pending_quiz 锁死随 ADR-0089 DROP COLUMN 作废，**不再实现**；03(a) follow-up chips **已 done**（commit `59872f8`）：统一 `build_actions` 入口 + SSE `suggested_actions` 新帧（不落库）+ 前端给定列表模式渲染。ai-prompts-hardening epic **全闭环**（01+02+03(a)），并已 `--no-ff` 合入 main（merge `f183c7f` + fix `4748f58`）+ 推送 origin（`58f7fac..4748f58`，含 ADR-0088-0091/0090）。

## 8. 分支卫生与合并台账（2026-10-15 大盘点后）
- **本地长期只有 `main` 一个分支**；integration/ticket 分支合入即删（`git branch -d` 有未合入保护）。曾有分支：adr-0088-0091、ai-prompts-hardening、tool-input-schema-slot-filling、conversation-ownership、replay-structured-extras、slots-01/02/03——全部已合入并删除。
- **slot-filling 线是后来才真正进 main 的**：早期「已合入 main」的记录与仓库现状不符（内容实际只在分支上），2026-10-15 按 `4fe9f81`(ADR-0095) → `0629b63`(ADR-0096) → `db05e35`(回放补全) 三个 `--no-ff` 合并补齐，合并后主仓复跑绿才删分支。**教训：「记忆/记录说合过了」不可信，以 `git branch --no-merged main` 与 `git log main..<branch>` 实测为准。**
- main 现 `6ad7bb6` ahead origin/main **1**（2026-10-19 22:48 并行会话把触发词收紧 `6489a97` 推到 origin，随后本地 `6ad7bb6` 对话导出未推）。ADR-0098 分支仍未合（用户令暂停）：合并时 `tasks/manifest.py`（学情行同 hunk）与 `question/manifest.py`（modify/delete）必冲突；裁决方向：把「哪些错题/错题有哪些/错题情况」并入合并版学情段，把「删裸词题目/练」带进 generate 组。

## 9. ADR-0098 二执行体收敛（分支 `integration/two-execution-bodies`，5 提交全绿，**未合 main**）
- 拓扑终态：执行体 **tasks / tutor**（students→tasks 票 01、question→tasks 票 02/03）；capability 零 LLM 固定回复不计执行体。tasks = 学情 8 工具（7 读+create_draft）+ 题库 3 + 出题流式 1 = 12。
- **slot filling 意图分组**（最实质机制变更）：manifest `intent_schemas.generate`（出题必填槽）；router `classify`→`Classification(business,trigger,level)`、`RouteDecision.trigger`；service `_resolve_input_schema(business,trigger)` 选 schema；槽位两本账 `business`（默认意图）/`business:intent`（如 `tasks:generate`）；specs 注入条件 `intent=="generate"`。词序即子意图（`_rule_match` 返回首个命中词；题库词不在 generate 组）；契约测试守 `intent_schemas⊆triggers`。
- 等价验证基线：**976 passed / 1 failed（materials `test_empty_text_422` 环境性红）/ 2 skipped**，与 main 同。提交链 9db4c7d→54b4a54→47ea91a→ba6428a（机制层）→3090d1c（合并波次，原子性：删 question/ 斩断测试 import，必须同提交）。
- **提交纪律**：`git add <部分>` 后**不带 pathspec** 的 `git commit` 会连带提交索引里已暂存的删除/改名——提交前必先 `git diff --cached --stat` 核对。

## 10. 意图路由终态：规则路由整体移除（ADR-0104，2026-10-20，分支 `ticket/08-decision-routing` 未合 main）
- **§9 的 slot filling 部分已被本节废止**：`intent_schemas`/`RouteDecision.trigger`/`business:intent` 两本账/`_business_triggered`/specs 聊天侧注入/汇总帧全部随 ADR-0104 删除；槽位回归每 business 单键，旧键行不读无需迁移。
- 路由链：动作直配（ADR-0081，等值匹配，永远最前）→ `decision`（LayaDecisionModel，`agent_core/adapters/laya.py`，**仅 `laya-multilingual`**，英文 laya 构造即 ValueError）→ `llm`（`classify_llm`，`adapters/llm_route.py`，`RoutingDecision(SQLModel)` 只落适配器保内核 stdlib-only）→ 都没有命中 → **无命中引导**：manifest 声明 `fallback_guide=True` 的业务（生产=capability 能力自述，零 LLM 固定清单，ADR-0105）；执行体（tasks/tutor）必须被显式路由到，`min(priority)` 仅是无声明时的最后防线（当前不可达）。策略 `AI_ROUTING_STRATEGY`：`llm=[llm]`/`decision=[decision,llm]`/`auto=[decision,llm]`（默认）。
- 上下文：`decide(history=…)` 全量透传（近期 12 轮裁剪），manifest 的 name/description/actions 经 `_capability_text` 作候选选项——「每轮带全量上下文、按能力路由」即此。
- **纯 LLM 出题（用户接受的 UX 降级）**：聊天出题无澄清引导、无规格回显、无 specs 注入，自由文本生成；按规格结构化出题仍走 `POST /tasks/generate`。通用槽位引擎（`fill_slots`/`clarify_sentence`/DONE 补发 726dba9）保留但聊天层暂不可达（manifest 全 optional），由 `required_slots` 合成 schema 守护。
- 测试确定性来源 = 路由桩显式表态：`FakeLLMProvider(route_to=...)`（schema 为 RoutingDecision 时表态）+ `RoutingFakeProvider`；**禁止在测试替身里复刻关键词匹配**。都不命中恒落 capability（8 句回归表 + 契约「至多一个 fallback_guide 声明 + 双端可见」守护）；学生 TutorLog 仅显式 tutor 轮落库。`tests/ai` 355 passed；全量基线 1003 passed/2 skipped/1 failed（materials `test_empty_text_422` 环境性红，与 main 同）。
- scratch：`.scratch/ai-intent-routing/`（spec INDEX + issues 01–10 全 done；gh 未登录仅本地）。工单 09 推翻 08「规则兜底」纪律；工单 10（ADR-0105）把 ADR-0104 §2.1 兜底子句从「min(priority)=tutor」改为「fallback_guide 声明=capability 能力引导」。
