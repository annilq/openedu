# openedu · 项目长期约定

> 权威设计/令牌/原则在 `.impeccable.md` + `docs/adr/` + `docs/agents/*.md`；术语 `CONTEXT.md`；入口 `AGENTS.md`。本文件只留**实测数字/归因/操作纪律**。⚠️ 注入上限 ~11.5k 字符，超则截断：新增前先删等量旧话。

## 0. 环境/命令/多会话
- Flutter SDK `/Users/annilq/Documents/fulttersdk/flutter`（不在 PATH）。`flutter test` **必先关代理**（`no_proxy="127.0.0.1,localhost,::1" NO_PROXY=同`，否则 `Invalid WebSocket upgrade request`）。`flutter analyze` 退出码常非0 → 认 `No issues found!`。
- 禁 `dart format`（本机 tall style 不同 → 噪声 diff）；只靠 analyze。新增原生插件须完整重跑 App（Hot Restart 不补原生注册 → pigeon `channel-error`）。
- 多会话并行改共享文件：先看 `git status`+mtime，定点 Edit，写完回读（本文件被并发整写覆盖过两次）。
- ⚠️ **并行 worktree 配方**：`git worktree add /tmp/oedu-tXX -b ticket/XX <base>` + `ln -s <主仓>/backend/.venv` 与 `.env`；**pytest 必须 `PYTHONPATH=/private/tmp/oedu-tXX/backend`**（venv 的 `_editable_impl_app.pth` 把 `app` 硬指向主检出，不带则 import 旧码得假结果）。配 `mv .env .env.hidden`+`--basetemp=/tmp/<新>`。
- 本机 `/bin/bash`=**3.2**：`$VAR` 紧跟中文字符会吞多字节首字节 → `unbound variable`，变量引用一律写 `${VAR}`；脚本被 zsh 调用需 `exec bash "$0" "$@"`。
- 演示成片管线（`submission_docs/`：`record_app.sh`→`gen_voice.py`→`gen_subs.py --all`）：时间轴取实测（ffprobe，不信 narration）；`tpad` 定格补帧必在 `fps` 之后；libass `FontSize` 非像素（无 PlayRes 的 SRT 按 288 基准）。
- 新 ADR 取号前查目录最大号 + `git status docs/adr/` + memory 预留（撞车三次 0055/0058）。
- SwiftPM 走 libgit2：不读 `http_proxy`、不认 `insteadOf`；唯一生效 SwiftPM mirror（`~/.swiftpm/...` + 工程 `xcshareddata/...`）。
- 文案纪律：**统一写「中小学」，不写 K12**；本项目「中小学」= **1–9 年级（小学+初中，义务教育），不含高中**。
- 提交材料 docx 由 `submission_docs/gen.py` 生成（python-docx 默认 Letter 纸，可用宽仅 15.24cm → 表格用 `set_col_widths` 钉住；run 不继承正文样式须 `set_run_font`；本机无 LibreOffice → 只程序化校验）。

## 1. 前端分层（ADR-0036/0037）
- AI 唯一入口 `assistantNotifierProvider`+`AssistantMessageList`；后端唯一端点 `POST /api/v1/assistant/chat`。助手路由优先级即功能（ADR-0054）：写意图 `guide`(20) 高于只读 `query`(12)。
- 卡片动作受控枚举 `actions=[{label,target}]`（target 非 URL）；`ShellDestination.fromTarget` 解读，认不出即不动；新增 target 两端同改。
- ⚠️ 结构化动作键 = manifest `actions` **等值**匹配（ADR-0081）：`task_generate`/`quiz_generate`/`courseware_generate`/`courseware_hint`/`quiz_judge`。⚠️ 服务端「重生成」**已全删**（ADR-0084）：出题唯一路径 = `POST /tasks/generate`（流式）+ `/tasks/from-generated`（落库）。
- ⚠️ 课件内容**纯手动编排**（ADR-0085）：`POST /courseware` 恒建零环节空壳 → 编辑器「添加环节」→ `PUT /sections` 整体覆盖写。
- 单向 `main/ → features/* → shared/*`；`shared/` 不 import `features/`；各 feature 有 repository、不建 datasource。
- ⚠️ R4 棘轮：`presentation/` 不得 import `*/data/`（`test/feature_boundaries_test.dart`）。要用 data 类型 → 搬 `domain/repositories/`，data/ 只留 `Impl`。
- ⚠️ 非 push 路由页面禁裸 `Navigator.pop`（弹根栈=整个App→白屏）；走注入回调或 `maybePop`。

## 2. 视觉/控件实测
- ⚠️ 全仓禁用 Material 控件（`InkWell`/`Icons.`/`Scaffold`/`ListTile`/`Divider`/`Tooltip`）：根是 `ShadApp`+`CupertinoApp`，无 Material 祖先，构建期即抛「No Material widget found」且 analyze 照不出来 → 新控件测试须在不套 Material 的树里真构建。可点区一律 `AppFocusableAction`。
- 描边三档：2/1.5/1（`borderWidth`/`borderWidthSm`/`borderWidthHairline`）。白物体在纸底 `#FDFBF7` 无边界（`surfaceRaised` 仅差~1.02）→ 补描边非加粗。
- 空态 `AppEmptyState`(ADR-0051)。reduce-motion 须 `reducedMotionOf(context)?Duration.zero:…`。
- ⚠️ `ShadButton.height` 是内容盒高，描边画盒外 → 可见高=值+2×描边宽（声明32**实测40**）；并排按钮一律 `Wrap`。`ShadCard` 比内容高时内容贴顶不居中 → 钉高调用点自包 `Center`。`Row(stretch)` 须包 `IntrinsicHeight`。
- ⚠️ ADR-0083：几何**单源在 `figure_library` 表**；`gen_figures.py`+parity 锁已退役。`SceneSpec={kind,points,edges}` 内联几何，运行时零图库依赖。多图形不平铺：图形画廊（条目顺序即渲染顺序）+ 弹 `ReflectionSceneDialog`。

## 3. 自适应布局（ADR-0045/0059）
- `AdaptiveShell` 两档：紧凑<700=娃娃底栏/家长抽屉；≥700=侧栏240↔64。
- ⚠️ 导航状态必须单一：`sealed ParentPage`/`TeacherPage`，所有入口只调 `_go(page)`；并列状态⇒必漏清且 analyze 照不出。
- ⚠️ 文件规模棘轮（ADR-0058）：`test/file_size_guard_test.dart` 的 `_baseline` 只许下调，新文件>400行直拦；搬代码块禁用正则删方法（DOTALL `.*?` 会跨吞下一方法 body → 逐行原样搬）。
- 桌面窗口地板 320×568；六平台目录未进版本控制 → 改完须 `flutter build`。
- 内容兜底须 `Align(topCenter)`+`ConstrainedBox`，不可 `Center`。`Navigator.push` 整页走 `AppContentFrame`+退路 `AppPushedPage`(`showBack`默认true)。

## 4. 测试/截图探针
- ⚠️ `ShadApp.custom(appBuilder:)` 不装 `ShadToaster` → widget 测试用 appBuilder 须显式 `ShadToaster(child:)`，否则 `AppToast.show` 抛「Could not find ShadToaster」。
- ⚠️ **禁止在 `test/` 里写截图装置**：`RenderRepaintBoundary.toImage()` 在无真实合成器时永不完成（实测 46s→17min）。要目检改几何断言（`getSize`/字段比对）。
- 网络层加接口要同步 4 个测试替身（`assistant_api_client_test`/`list_archive_test`/`review_notifier_test`/`students_notifier_test`），漏一个整条 test 编译不过。
- 静态护栏（扫源码类 `test/*_test.dart`）**误报比漏报更坑**：子串匹配一律**词边界锚定**——`contains('BarChart(')` 被 `AppBarChart(` 骗到；判 import 还要引号不敏感。

## 5. Git/后端/长列表
- 平台目录不在版本控制 → 打补丁脚本（`frontend/scripts/patch_macos_network.py`、`patch_voice_permissions.py`），幂等+`--check`。常显 `Everything up-to-date` 却已成功 → `git ls-remote origin main` 比对 HEAD。提交按逻辑批次拆、正文写「为什么」；`chore(memory):` 单独提交。
- ⚠️ `git commit -- <file>` 会重暂存该文件整个工作区 → hunk 级拆分须 `git add -p` 后**不带 pathspec** `git commit`。
- 引擎失败归因：`decrypt()` 解不开只返 `None`；`ToolUnsupportedError` vs `ProviderRequestError`(`kind`+`user_hint`)；禁 `except Exception` 抹成「请添加模型」。
- ⚠️ 可空 JSON 列须 `JSON(none_as_null=True)`（否则 `None` 序列化成 `'null'` → `IS NOT NULL` 为真而内容空）。
- ⚠️ 选项标号只由渲染层画且必须同时剥模型前缀（ADR-0061 §T）；后端 `normalize_options` 刻意不剥。`tests/ai/test_option_prefix_contract.py` 守。
- ⚠️ SQLite「加列」≠「加约束」（ADR-0061 §R）：`ADD COLUMN` 里的 `UNIQUE` 被静默忽略 → 老库仍留旧约束。改 UNIQUE 须重建表。
- pytest 前 `cd backend && mv .env .env.hidden`（完恢复）；`.venv/bin/ruff`/`.venv/bin/pytest`（全量~25s）。沙盒必 `--basetemp=/tmp/<新目录>`。真库 `backend/app.db`（相对 backend）→ 必先 `cd backend`。
- ⚠️ 分层不变量9：归属判定只许走 `core.guard`(`require_owned`/`find_owned`/`require_owned_child`)，禁内联 `x.parent_id!=y`；AST 守卫 `tests/ai/test_layering_invariants.py`。改 `features/*/service.py` 必跑 `tests/ai/`。
- ADR-0064 多选删除：`POST /materials/bulk-delete`+`/materials/knowledge-points/bulk-delete`。KP↔Material 无外键、只靠名字串。
- ADR-0055 资料库+RAG：4表全带 parent_id；向量存 BLOB；`EMBEDDING_MODEL` 兼向量版本戳；`build_retriever(session,parent_id)` 新签名。
- ⚠️ ADR-0073：`KnowledgePoint.scenes` 是唯一事实源；`get_builtin_scene` 必返深拷贝；统一入口 `resolve_kp_scene`。AI 答疑命中图库图形才 emit `interactive_scene`。
- ⚠️ 同一实体两份 schema：`features/*/service.py`（助手工具投影）与 `router.py`+`schemas.py`（REST）。前端打 REST——「下发了 X」必须打到端点验。

## 6. 题型模型（ADR-0004 D5）
- qtype 域 `{choice,fill,calc,open}`（后端权威）。多选 `multi:bool`（默认False），跨 10 模型+启动期 ALTER；`TaskSpec.multi=True` 仅允许 `qtype=='choice'`（否422）。
- 判断题：无独立类型，`choice`+对/错二选一（前端 `isJudgeQuestion`）。选择题须带≥2有效选项，否则拦 `TASK_CHOICE_NO_OPTIONS(422)`。

## 7. 班级管理（ADR-0068 后端 + 0086 前端）
- 后端（ADR-0068）**已全落地**：`Class` 实体（`teacher_id,name,grade(1–9),created_at`）+ `User.class_id`（可空 FK）；`GET/POST/PATCH/DELETE /classes`（列表带 `student_count`）；`GET /students?class_id=&keyword=`、批量移班 `POST /students/batch-reassign`、xlsx 导入/导出、带级联清理的删除；已注册 `main.py`。
- 前端**缺口**：`features/classes/` 只有 `data/`+`providers/`，**缺 `presentation/`**；`student_management_screen.dart` 已按班级分组/筛选/批量移班，但无建改删班级的入口与导航落点。
- ADR-0086（前端容器+下钻）：新增「班级管理」一级导航（`TeacherPage.classManagement`），班级卡片列表 → 点班级下钻到该班学生管理页（push `AppPushedPage`）；原「学生管理」保留为全部学生扁平视图。班级内学生操作全量（查看/单个添加+导入/批量移班/删除）。
- 年级语义（0086，**2026-10-11 反转**）：学生**不持年级字段**，`user.grade` 已全删；年级完全由所属 `Class.grade` 承载（班级名可直接编码，如 `1级2班`）。消费方一律经 `user.class_id`→`class.grade` 解析（唯一入口 `assistant.service._student_grade`，未分班返 0）；`UserBase` 删 `grade` 列、`core/db.py` 迁移 `DROP COLUMN grade`、`auth/schemas.UserUpdate`+`auth/repository.update_user`+`students/router` 同步移除 `grade` 形参。
- 后端小扩展（0086）：`POST /students` 与 `POST /students/import` 增加可选 `class_id`（直接归入本班）。
