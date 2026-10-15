# openedu · 项目长期约定
> 权威源 `.impeccable.md`/`docs/adr/`/`docs/agents/*.md`；术语 `CONTEXT.md`；入口 `AGENTS.md`。只留实测数字/归因/操作纪律。

## 0. 环境/命令
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）；`flutter test`/`analyze` 须 `no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同`（WS 升级失败）；`flutter analyze` 退出码非0→认 `No issues found!`。
- 禁 `dart format`（本机 tall style 噪声）；新增原生插件须完整重跑 App（Hot Restart 不补原生注册→pigeon channel-error）。并行 worktree：`git worktree add /tmp/oedu-tXX -b ticket/XX <base>`+软链 `backend/.venv`/`.env`；worktree 下 pytest 须 `PYTHONPATH=/private/tmp/oedu-tXX/backend`。
- **后端全量 pytest 必带 `--basetemp=/tmp/<新目录>`**（主仓同样）：默认 `/private/var/folders/.../pytest-of-root` 的 mkdir 被沙箱拒 → 几十条 setup ERROR（courseware/migration 一批文件），极易误判成自己写的回归；单文件跑不受影响。跑完记得 `mv .env.hidden .env` 还原。

## 1. 前端分层
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`（写意图 `guide`(20)>只读 `query`(12)）。结构化键=manifest `actions`(ADR-0081)：`task_generate`/`quiz_generate`/`courseware_hint`/`quiz_judge`。出题=`POST /tasks/generate`(流式)+`/tasks/from-generated`(重生成全删)。单向 `main/→features/*→shared/*`；R4：`presentation/` 禁 import `*/data/`(测试 `feature_boundaries_test.dart`)。

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
- main 现 ahead origin/main 39（含全部上述内容，**未推送**——推送时机留用户）。
