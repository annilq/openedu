# openedu · 项目长期约定
> 权威源 `.impeccable.md`/`docs/adr/`/`docs/agents/*.md`；术语 `CONTEXT.md`；入口 `AGENTS.md`。只留实测数字/归因/操作纪律。

## 0. 环境/命令
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）；`flutter test`/`analyze` 须 `no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同`（WS 升级失败）；`flutter analyze` 退出码非0→认 `No issues found!`。
- 禁 `dart format`（本机 tall style 噪声）；新增原生插件须完整重跑 App（Hot Restart 不补原生注册→pigeon channel-error）。并行 worktree：`git worktree add /tmp/oedu-tXX -b ticket/XX <base>`+软链 `backend/.venv`/`.env`；worktree 下 pytest 须 `PYTHONPATH=/private/tmp/oedu-tXX/backend`。
- **后端全量 pytest 必带 `--basetemp=/tmp/<新目录>`**（主仓同样）：默认 `/private/var/folders/.../pytest-of-root` 的 mkdir 被沙箱拒 → 几十条 setup ERROR（courseware/migration 一批），极易误判成自己写的回归；单文件跑不受影响。pytest 前 `cd backend && mv .env .env.hidden`、跑完 `mv` 还原（`.venv/bin/pytest` ~25s；真库 `backend/app.db`→必先 `cd backend`）。
- git：提交按逻辑批次拆、`chore(memory):` 单独提交；`git commit -- <file>` 重暂存整个工作区→`git add -p` 后不带 pathspec `git commit`；**不带 pathspec 的 commit 会连带提交索引里已暂存的删除/改名**——提交前必 `git diff --cached --stat` 核对。仓库状态以 `git branch --no-merged main`/`git log main..<branch>` 实测为准，**记忆说「合过了」不可信**。
- 2026-10-20 现状：main == origin/main == `0591f92`（T08–T11 全在主线且已推送）；长期分支只有 main，ticket/integration 分支合入即删；当前工作分支 `integration/ai-redundancy-cleanup`（+`39d762b`，另一条线：AI 冗余清理 spec 5 候选）。

## 1. 前端分层
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`。结构化键=manifest `actions`(ADR-0081)：`task_generate`。出题=`POST /tasks/generate`(流式)+`/tasks/from-generated`(重生成全删)。单向 `main/→features/*→shared/*`；R4：`presentation/` 禁 import `*/data/`（测试 `feature_boundaries_test.dart`）。
- 潜伏缺口：**流式题卡无 `scene_spec` 生产者**（`GeneratedQuestion` 无此字段、`generate_questions` 不构建）→ 聊天题卡永远无图，只有落库后的任务/题库页读 `scene_spec_for_read`。tutor 侧 `interactive_scene`（L0/L1/L2）与出题侧互不复用；题卡 options 走 `cardStr`，与 `QuizOption.parseList` 形状不一致。

## 2. 视觉/控件（analyze 照不出）
- 禁用 Material 控件(`InkWell`/`Icons.`/`Scaffold`/`ListTile`/`Divider`/`Tooltip`)：根 `ShadApp`+`CupertinoApp` 无 Material 祖先→抛「No Material widget found」。可点区一律 `AppFocusableAction`。
- `ShadButton.height` 内容盒高+描边画盒外→可见高=值+2×描边宽(声明32实测40)；并排按钮 `Wrap`。`ShadCard` 高于内容→调用点自包 `Center`。`Row(stretch)` 须包 `IntrinsicHeight`（裸必崩；**子树含 `LayoutBuilder` 也崩**）；`Column(stretch)` 安全。色条=`Stack`+左 `Container`+卡片 clip 裁圆角（非均匀 Border 喂 ShadCard 抛 `borders with uniform colors`）。白物体纸底 `#FDFBF7`→补描边。

## 3. 自适应/布局(ADR-0045/0059)
- `AdaptiveShell`：紧凑<700=娃娃底栏/家长抽屉；≥700=侧栏240↔64。导航单一：`sealed ParentPage`/`TeacherPage` 只调 `_go(page)`。文件规模棘轮(ADR-0058)：`file_size_guard_test.dart` `_baseline` 只许下调，新文件>400行直拦；搬代码禁正则删方法(逐行搬)。内容兜底 `Align(topCenter)`+`ConstrainedBox`(非 `Center`)。push 整页 `AppContentFrame`+`AppPushedPage`(`showBack`默认true)。

## 4. 测试纪律
- Flutter：`ShadApp.custom(appBuilder:)` 不装 `ShadToaster`→widget 测试须显式 `ShadToaster(child:)`。禁 `test/` 写截图装置（`RenderRepaintBoundary.toImage()` 无合成器永不完成→改几何断言）。网络层加接口须同步 4 测试替身(`assistant_api_client_test`/`list_archive_test`/`review_notifier_test`/`students_notifier_test`)。长按 `startGesture`+`pump(kLongPressTimeout)`。
- 后端：引擎失败 `decrypt()` 解不开只返 None；`ToolUnsupportedError` vs `ProviderRequestError(kind+user_hint)`（`genkit.py#classify_failure`）；禁 `except Exception`。可空 JSON 列须 `JSON(none_as_null=True)`(ADR-0061)；SQLite「加列」≠「加约束」→改 UNIQUE 须重建表。选项标号只渲染层画+剥前缀：`cleanOptionText`。长列表(ADR-0053) keyset 游标；读错题加 `graduated_at IS NULL`。
- 分层不变量9：归属只许 `core.guard`(`require_owned`/`find_owned`/`require_owned_child`/会话三件套)，禁内联；AST 守卫 `tests/ai/test_layering_invariants.py`（只认 `!=`/`is not`，SQL 里的 `==` 过滤不算违规）。改 `features/*/service.py` 必跑 `tests/ai/`。同一实体两份 schema：`features/*/service.py`(助手投影)与 `router.py`+`schemas.py`(REST)；前端打 REST。
- 全量基线：**1003~1015 passed / 2 skipped / 1 failed**，唯一失败恒为 `materials test_empty_text_422`（已知环境性红，与 main 同）。ruff 既有债（specs.py I001+F401×4、test_assistant F841、tasks_write_intent F401×2 等）用 `git show HEAD:<file> | ruff check -` 区分，只修自己引入的。

## 5. 题型/班级/历史 epic（已闭环，仅留结论）
- 题型(ADR-0004 D5)：qtype `{choice,fill,calc,open}`；选择题≥2 选项(`TASK_CHOICE_NO_OPTIONS(422)`)；多选 `multi:bool` 仅 `choice`；判断题=`choice`+对/错。`Conversation.pending_quiz` 已删(ADR-0090)。
- 班级(ADR-0068+0086)：`Class`(`teacher_id,name,grade(1–9)`)+`User.class_id`；年级由 `Class.grade` 承载，`user.grade` 全删；前端缺 `features/classes/presentation/`。
- ADR-0088/0089/0090/0091 全 done；ai-prompts-hardening epic（capability ADR-0079 / 知识点聚焦 ADR-0080 / follow-up chips）全闭环并 `--no-ff` 合入 main。工单只在本地 `.scratch/<topic>/`（gh 未登录未转 issue）。

## 6. 会话归属 = 本人可见（ADR-0096）
- 判据唯一真源 `core.guard.conversation_owner_clause(user)`：学生 `student_id==me`；教师/admin `teacher_id==me AND student_id IS NULL`（教师**看不**到学生的）。三消费者同源（列表/详情/批量删除）——分家必出「列表能列出、详情 403」。
- `Conversation.teacher_id` ≠ 归属（它表示教学域：RAG 范围、`resolve_engine`），故不加 `owner_user_id` 列。会话三端点 `CallerDep` 双端通用；响应无 `student_id`/`student_name`；前端无只读态。审计走 `/ai/debug/conversations`。

## 7. 意图路由终态（ADR-0104 移除规则路由 + ADR-0105 无命中引导）
- 路由链：**动作直配**（ADR-0081，等值匹配、恒最前、不参与优先级竞争；命中但角色不可见→显式 `action_not_visible`，禁止静默换业务）→ `decision`（`agent_core/adapters/laya.py`）→ `llm`（`classify_llm`，`RoutionDecision(SQLModel)` 只落适配器，保内核 stdlib-only）→ 都没命中 → **无命中引导**（manifest 声明 `fallback_guide=True` 的业务，生产=capability 零 LLM 固定清单）；执行体 tasks/tutor **必须被显式路由到**，`min(priority)` 只是无声明时的最后防线（当前不可达）。策略 `AI_ROUTING_STRATEGY`：`llm=[llm]`/`decision=[decision,llm]`/`auto=[decision,llm]`（默认）。
- 上下文：`decide(history=…)` 透传近期 12 轮（`ROUTING_HISTORY_LIMIT`，按 laya 1024 tok 调），manifest 的 name/description/actions 经 `_capability_text` 作候选——「每轮全量上下文 + 按能力路由」即此。`priority` 只剩「清单呈现顺序」语义。
- ADR-0104 一并删除：`classify`/`_rule_match`/启发式/`triggers`/`hints`/`trigger_patterns`/`intent_schemas`/`RouteDecision.trigger`/`business:intent` 两本账/specs 聊天注入/汇总帧。聊天出题改**纯 LLM 自由文本生成**（无澄清、无规格回显；结构化出题仍走 `POST /tasks/generate`）。通用槽位引擎（`fill_slots`/`clarify_sentence`/DONE 补发）保留但聊天层暂不可达，由 `required_slots` 合成 schema 守护。
- 测试确定性来源 = 路由桩显式表态：`FakeLLMProvider(route_to=...)`（schema 为 RoutingDecision 时表态）+ `RoutingFakeProvider`；**禁止在替身里复刻关键词匹配**。都不命中恒落 capability（8 句回归表 + 契约「至多一个 fallback_guide 声明 + 双端可见」）。学生 TutorLog 仅显式 tutor 轮落库。

## 8. 决策模型：本地 Ollaya + 中文实测（ticket 11）
- 本机 `ollaya` 0.15.0（`/usr/local/bin`，与 Ollama 11434 并存），服务 `127.0.0.1:11435`，TypeSafe 兼容 `POST /v1/systemone`；模型缓存 `~/.ollaya/models`。已拉 `laya:multilingual`(683 MB)、`largha`(328 MB，实测否决)。命令：`ollaya serve/list/ps/pull/run`。
- payload = `{model, state, questions:{id:{type:"choice",instructions,criteria:{业务键: capability_text}}}}`，响应 `answers[id].{choice,confidence,probabilities}`。旧形状 `{"state","questions":[{...}]}` 直连实测 `422 INVALID_REQUEST`（`model` 必填、`questions` 必须 dict）——**曾是从未验证的纸面契约**。
- **门控用 `probabilities` top 值，不用 TypeSafe `confidence`**（后者 `=(K·pmax−1)/(K−1)`，同一置信在教师端 K=3 / 学生端 K=2 是两个数字；实测 pmax 0.823→confidence 0.7345）。env：`OLLAYA_URL`（原 `LAYA_SERVE_URL`）、可选 `OLLAYA_MODEL`；模型参数为 **ollaya 标签**（白名单 `laya:multilingual`/`largha`，英文权重构造即 ValueError）。失败面（未配置/非 2xx/超时/异常）统一 → None → 回落 LLM 分类 → 再不中落能力引导；state 超长 → `422 STATE_TRUNCATED` 同路径。
- **中文影子评测**（`.scratch/ai-intent-routing/eval/decision_model_eval.py`，pytest 之外、可复跑）：13 条中文用例 + 12 轮长历史(719 字符)。`laya:multilingual` **8/13=62%**、p50 23 ms、平均置信 0.617、长历史不截断；`largha` 5/13=38%、平均置信 0.270（阈值 0.5 下近乎恒不决策）、长历史 **422 截断**。→ 推翻上一轮按公开英文基准做的「largha 首选升级」推断。**纪律：候选取舍必须有本项目中文数据，低于现任不得进白名单。**
- 失分（实测）：T04 查学情→tutor(0.598)、T05 查错题→capability(0.432 vs tasks 0.427)、T07 纯讲解→tasks(0.674)、T10 续接转讲解→tasks(0.544)、**S01 学生「23+45 怎么算」→capability @0.956（高置信错误，最坏）**。共同根因=三者 criteria 文本可分性。
- 本机注记：Apple silicon 走 MLX（10–30 ms）；虽有 `HTTP_PROXY` 且无 `no_proxy`，实测 urllib 对 localhost 自动绕过（**不要**加 ProxyHandler 旁路代码）。

## 9. 路由调优次序（用户 2026-10-20 定序，ticket 12/13）
- **文案 → 门控 → 权重**。ticket 12（`ready-for-agent`）：只改三个 manifest 的 `name`/`description`（即 `criteria` 值），用同一脚本量化；脚本改吃生产投影（`discover_subagent_manifests`+`_capability_text`）消除手抄副本；用例集 13 → ~30 条（每条失败用例补近邻）并**先用旧文案建对照基线**；单变量迭代；验收线=教师端不低于基线且无 pmax≥0.8 的错误、学生端 S01 必须翻正、长历史不截断；达不到才启用 `routing_criteria` 字段（需在 ADR-0097 上补修订）。
- ticket 13（`needs-decision`，等 12 的数据）：把阈值从适配器构造参数上移为 runtime 的**声明式门控**（决策模型只出分布、runtime 决定是否采纳；LLM 的 confidence 一并纳入——今天它完全没被门控），再谈「学生端单独阈值」与「与 LLM 交叉校验(consensus)」。否决：把 role 塞进适配器、把 consensus 设为默认（每轮多一次 LLM 往返）。
- **capability 误判代价不对称**：判成 capability 与「都没命中」在用户侧同形（ADR-0105），判成执行体会答非所问 → 不应共用同一采纳门槛。
- 改 `description` 会同时改用户可见能力清单（`capability_catalog`「name：description」）与轨迹业务名 → 同步核对 `test_capability_subagent`/`test_assistant`/`test_tasks_subagent`/`test_intent_routing_contract`/`test_agent_runtime` 的断言；**只更新断言不改语义**；文案若变得不像人话即启用 `routing_criteria` 熔断。
