# ADR-0088 · AI 运行轨迹可观测 UI 与 admin 监管

- **状态**：提案（待评审）
- **日期**：2026-10-12
- **分支**：`ai-intent-routing`
- **取号**：本分支最大已接受 ADR 为 0087，顺延取 0088（注：`docs/adr/` 内已存在两份 0086 撞号文件，不沿用其号）。

---

## 1. 背景（Context）

经代码实态核查（2026-10-12），AI 运行的可观测性当前处于「后端有、客户端无、字段空」的状态：

- **后端已有运行轨迹端点**：`GET /ai/debug/conversations` 与 `GET /ai/debug/conversations/{conv_id}`（`backend/app/features/ai/router.py:29,38`），返回 `ConversationResp` + `MessageResp`（`schemas.py:24`，含 `role/step/content/payload/model/usage/latency_ms/input_safe/output_safe/blocked/block_reason`），权限走 `core.guard.require_owned(teacher.id)`，只读回放。这是 ADR-0022/0026 的「教师可见调试轨迹」，读的是与聊天同一张 `Conversation`/`Message` 表。
- **客户端零 UI**：前端全仓无路由 / provider / 页面调用 `/ai/debug/conversations`；`conversation.dart:10-11` 注释明写运行轨迹「不进气泡」。该端点是纯服务端能力。
- **可观测字段在生产代码里全空**：`Message` 模型已声明 `latency_ms`/`usage`/`model`/`input_safe`/`output_safe`/`blocked`/`block_reason`（`db/models/conversation.py:51-67`），但 `service.py` 的落库路径（约 663–719 行）只写 `conversation_id/turn/role/step/content/payload`——其余字段未填。
- **三个「看过去」的表面已经分叉，但都缺入口/字段**：
  - **历史会话**（`/assistant/conversations` → `AssistantBubble` 仅 `role/text/cards`）：使用者视角的**气泡投影**，剥离了所有内部步骤。
  - **运行轨迹**（`/ai/debug/conversations`）：审计 / 排障视角的**全部步骤投影**（含路由、工具调用与结果、原始载荷）。
  - **伴学审计**（`/tutor/logs`，F-305）：儿童安全审计（伴学说了什么、是否被拦截），读独立的 `TutorLog` 表。
  三者受众同（教师），关注点不同，已在术语表区分（CONTEXT.md §运行轨迹：日志指伴学的 TutorLog）。
- **鉴权无 admin 角色**：`auth` 的 `role` 是自由字符串（`auth/repository.py:22` 只传 `"teacher"`）；`core/guard.py` 只有 `require_owned(owner_id=teacher.id)`（`:28,44`），**无跨教师读取能力**。

诉求：让教师（及一个跨教师的监管角色）能看到 AI 运行轨迹——含路由决策、工具调用与结果、模型、**token / 延迟 / 成本 / 安全标记**——且与历史会话、伴学审计不混淆。

---

## 2. 决策（Decision）

### 2.1 新增 `admin` 角色 + 启动 seed 默认账号

- `User.role` 增加 `'admin'`（自由字符串扩展，无枚举改动）。
- 启动期幂等 seed 默认 admin 账号；**密码取自环境变量或首次登录强制改密，绝不写死明文**（安全基线）。
- `core/guard.py` 新增 `require_owned_or_admin`：admin 短路跳过 `teacher_id` 归属校验，即「看全部」；teacher 仍只走 `require_owned`。

### 2.2 后端 debug 端点加 admin 口径

- `GET /ai/debug/conversations`：teacher 按 `teacher_id` 过滤看自己；admin 去掉该过滤看全部（加 `require_owned_or_admin`）。保留 `kind` 过滤与时间倒序。
- `GET /ai/debug/conversations/{id}`：teacher 仅自己（越权 403）；admin 任意（guard 短路）。

### 2.3 客户端独立「运行轨迹」页（镜像后端双消费者）

- 与**历史会话（气泡）并列**，**不进气泡、不混入历史详情**（呼应 `conversation.dart:10-11` 的「不进气泡」纪律，也呼应后端 `/assistant/conversations` 与 `/ai/debug/conversations` 是「两个消费者」的既有分离，`service.py:752` / `router.py:17`）。
- 教师看自己；admin 看全部。导航落点须遵守 ADR-0059 单源：`sealed TeacherPage` 扩展一个 case（admin 可复用同页、按角色切范围，或独立管理区），所有入口只调 `_go(page)`。

### 2.4 内容隐私：默认脱敏 + 破窗留痕

- **默认视图 = 元数据 / 审计**：`step` / 模型 / token / 延迟 / 安全标记（`blocked`/`block_reason`）/ 路由决策可见；**`tool` 参数与结果中的学生 PII 模糊化**（呼应首轮 `include_content=False` 原则与 ADR-0026 安全基调，儿童产品合规红线）。
- **全文内容**（原始 tool 参数 / 结果 / 路由原文）走 **break-glass**：显式请求 + 访问留痕（写一条 access log：谁、何时、读了哪段对话全文），不默认展开。

### 2.5 usage 落库（零 schema 改动）

- 在 `service.py` 落库路径补填每步的 `model`（已有列）、`usage`（token 字典：`prompt`/`completion`/`total`）、`latency_ms`（本步耗时）；`input_safe`/`output_safe`/`blocked`/`block_reason` 同步写实。
- **不新增 `Conversation` 列**：会话级总成本可由步级 `usage` 按 `conversation_id` 聚合得出（GROUP BY 即可），不冗余存储。先补落库，运行轨迹 UI 才能展示成本 / 延迟列。

### 2.6 三表面边界重申

历史会话（气泡，使用者视角）/ 运行轨迹（步骤 + 元数据，审计排障）/ 伴学审计 `TutorLog`（儿童安全）——受众同（教师 / admin）但关注点不同，**各自独立，不合并**。

---

## 3. 与既有 ADR 的关系

- **沿用 ADR-0026**：观测落库统一由 `app.features.assistant` 承担、安全基调；**沿用 ADR-0022**：调试轨迹端点。
- **扩展 CONTEXT.md §运行轨迹**：补 admin / 破窗 / usage 三个维度（见 §5 文档动作）。
- **遵守 ADR-0059**（教师端 sealed 单源导航）：新增运行轨迹落点须扩 `sealed TeacherPage`，禁止并行状态。
- **不引入框架自带 session memory**（首轮结论）：会话与观测继续走业务表，与 `agent_core` 不持有会话的分层不变量一致。
- **不触碰 ADR-0086 / 0087** 的班级管理 / 课件清理范围。

---

## 4. 实现拆分（落地顺序）

1. **usage 落库**（`service.py` 补 `model`/`usage`/`latency_ms`/`input_safe`/`output_safe`/`blocked`/`block_reason`）—— 解锁成本 / 延迟列，**零 schema 改动，最先做**。
2. **admin 角色 + seed + guard 短路**（`auth` + `core/guard.py`）。
3. **debug 端点加 admin 口径**（`router.py`）。
4. **客户端独立运行轨迹页 + 教师 / admin 导航落点**（`frontend`，遵守 ADR-0059）。
5. **内容脱敏 + 破窗访问留痕**（后端 mask + access log，前端破窗 UI）。
6. **文档**：本 ADR + CONTEXT.md 术语更新。

---

## 5. 文档动作（Documentation）

- 扩展 CONTEXT.md §运行轨迹：补「可观测 UI 表面」「admin 可跨教师」「破窗访问 + 脱敏」三句；新增 §角色「管理员 (Admin)」与「破窗访问 (Break-glass Access)」两条目。

---

## 6. 验证（Verification）

- `pytest tests/api/routes/test_assistant.py` 扩 debug 端点用例：admin 看全部 / teacher 仅自己 / 越权 403。
- `pytest` 全量 + `ruff check .` 改动文件全绿。
- `flutter test` 既有 `assistant_history_test` 类不被破坏；新增运行轨迹页测试（教师 / admin 两种范围）。
- 全仓 grep 验证 `Message` 落库路径确实写入 `usage`/`latency_ms`（非空）。

---

## 7. 开放问题

- admin 是否也需要看 `tutor_logs` 跨教师？当前方案 `tutor_logs` 保持教师域，admin 暂不含（如需再开）。
- 破窗访问留痕落库位置：新建 `access_log` 表，还是复用 `TutorLog` 字段？
- admin 在客户端的入口形态：复用运行轨迹页按角色切范围，还是独立管理区？（影响 ADR-0059 的 `sealed` 扩展方式）

---

## 8. 实施进度（2026-10-12）

账户角色已从自由字符串改为枚举，admin 落地与护栏已接通（与 §1/§2 决策一致）：

- **枚举定义**：`app/db/models/user.py` 新增 `Role(str, Enum)` = `STUDENT/TEACHER/ADMIN`。
  `UserBase.role` 改为 `Role` 类型，但 DB 列仍 `VARCHAR(16)`（`sa_column=Column(String(16))`，
  **无迁移**）；读写经 Pydantic 与枚举互转，历史字符串（`teacher`/`student`）兼容。
- **护栏**：`core/deps.py` 的 `require_teacher` 放行 `(TEACHER, ADMIN)`（admin=超级教师），
  新增 `require_admin` + `CurrentAdmin`；`require_student` 仅 `STUDENT`。
- **归属豁免**：`core/guard.py` 新增 `require_owned_or_admin`，admin 越教师边界只读审计/排障。
- **debug 端点**：`features/ai/router.py` 的两个端点现接受 `CurrentTeacher`（含 admin）；
  列表对 admin 传 `teacher_id=None`（看全部），详情走 `require_owned_or_admin`。
- **种子**：`core/config.py` 新增 `ADMIN_SEED_USERNAME`/`ADMIN_SEED_PASSWORD`（**两者皆配才创建**，
  绝不写死口令）；`main.py` 启动期幂等 seed 一个 `Role.ADMIN` 账号。
- **口径分离**：账户角色与 agent_core 的「调用面（surface, teacher/student）」严格分离——
  agent_core 业务无关、零 `app.*` 依赖，故 `assistant/service.py` 用 `_surface_of(role)`
  把账户角色折算成调用面（仅 student 走 student 面，teacher/admin 走 teacher 面）后再传入运行时。
- **验证**：`pytest` 全量 791 passed / 2 skipped；`ruff check` 改动文件全绿。
