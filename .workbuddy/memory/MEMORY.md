# openedu · 项目长期约定
> 权威源 `.impeccable.md`/`docs/adr/`/`docs/agents/*.md`；术语 `CONTEXT.md`；入口 `AGENTS.md`。只留实测数字/归因/操作纪律。

## 0. 环境/命令
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）；`flutter test`/`analyze` 须 `no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同`（WS 升级失败）；`flutter analyze` 退出码非0→认 `No issues found!`。
- 禁 `dart format`（本机 tall style 噪声）；新增原生插件须完整重跑 App（Hot Restart 不补原生注册→pigeon channel-error）。并行 worktree：`git worktree add /tmp/oedu-tXX -b ticket/XX <base>`+软链 `backend/.venv`/`.env`；pytest 须 `PYTHONPATH=/private/tmp/oedu-tXX/backend`+`mv .env .env.hidden`+`--basetemp=/tmp/<新>`。

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
- pytest 前 `cd backend && mv .env .env.hidden`；`.venv/bin/pytest` ~25s；真库 `backend/app.db`→必先 `cd backend`。长列表(ADR-0053)：keyset 游标；读错题加 `graduated_at IS NULL`。分层不变量9：归属只许 `core.guard`(`require_owned`/`find_owned`/`require_owned_child`)，禁内联；AST 守卫 `tests/ai/test_layering_invariants.py`；改 `features/*/service.py` 必跑 `tests/ai/`。同一实体两份 schema：`features/*/service.py`(助手投影)与 `router.py`+`schemas.py`(REST)；前端打 REST。`scene_spec_for_read`(ADR-0061 §U) 唯一交互讲解读路径。

## 6. 题型/班级/ADR 状态
- 题型(ADR-0004 D5)：qtype `{choice,fill,calc,open}`；选择题≥2 选项(`TASK_CHOICE_NO_OPTIONS(422)`)；多选 `multi:bool` 仅 `choice`。判断题=`choice`+对/错(`isJudgeQuestion`)；`Conversation.pending_quiz` 已删(ADR-0090)，`chat()` 直接 `IntentSignal`；tutor `_read_history`→`_question_card_text`。
- 班级管理(ADR-0068+0086)：后端 `Class`(`teacher_id,name,grade(1–9)`)+`User.class_id`；`/classes` CRUD+`/students?class_id=&keyword=`+导入导出；`POST /students`/`/students/import` 增 `class_id`；前端缺 `features/classes/presentation/`；ADR-0086 补「班级管理」(`TeacherPage.classManagement`)；年级由 `Class.grade` 承载，`user.grade` 全删。
- **ADR 状态：0088/0089/0090/0091 全 done**（集成分支 `integration/adr-0088-0091`）。0091=`SceneSpec` 直接持 `Figure`、几何归一、前端 `FigureShape` 补 `edges`；0089-04=前端选项内联图形(`QuizOption{text,figure?}`+`AppOptionTile` 行内缩略图+`ReflectionSceneDialog`，`flutter test` 543 passed)；0090=判断题闭环子代理化+修三前端既存红；0088=角色枚举+admin+运行轨迹页+脱敏破窗。详见 `docs/adr/`。
- **ai-prompts-hardening epic（3 票，独立集成分支 `integration/ai-prompts-hardening`）**：01 capability 意图 **done**(`00f78c0`+`f7c6766`)；02 kp 聚焦注入 tutor/query 系统提示 **done**(`ec67a75`，`kp_focus.py` 经 `find_owned` 取四元组、`tutor_system_prompt` 安全锁未动)；03(a) follow-up chips **未开工**（(b) pending_quiz 锁死已被 ADR-0089 删状态机而作废，仅剩 (a) SSE suggested_actions 帧+前端渲染）。
