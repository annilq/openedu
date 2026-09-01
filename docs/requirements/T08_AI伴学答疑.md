# T08 · 三期 AI 伴学答疑 MVP（F-302 / F-304 / F-305）

> 范围来源：PRD 全三期「三期 详细规格」F-301~F-305。F-301（知识库管理）与 F-305 的知识库检索前置（AC-305）因教材版权 🔴 硬门槛（ADR-012）**deferred**，本期仅做自由问答并预留检索接入点。

## 目标
让娃娃能就题目/知识点自由提问，AI 给出**适龄讲解**；全程套用**内容安全层**；家长可查全部 AI 交互日志。

## 验收（来自 PRD 三期验收标准）
- [x] AC-301 娃娃可自由提问并获得适龄讲解 → `POST /tutor/ask` + `TutorService.explain`
- [x] AC-302 越狱/敏感提问被拦截，娃娃看不到违规内容 → `domain/safety` 输入/输出双层校验，命中返回 `SAFE_REFUSAL`
- [x] AC-303 家长可查阅全部 AI 交互日志 → `GET /tutor/logs`
- [x] AC-304 达每日上限后拒答 → `TUTOR_DAILY_LIMIT` + `count_tutor_today` 返回 429（MVP 以**消息条数**计上限；时长上限为后续增强）
- [ ] AC-305 知识库就绪后优先基于检索结果（deferred，见 ADR-012）

## 实现要点
- **Provider 扩展**：`LLMProvider` ABC 新增 `async tutor()`；`LangChainProvider` 注入年龄锁系统提示 `tutor_system_prompt(grade, subject)`，`MockProvider` 返回模板讲解。
- **内容安全层** `domain/safety.py`：①系统层年龄锁 ②`check_input()`（越狱/非学习类，对 question+knowledge_point+context 统一校验，避免从知识点绕过）③`check_output()`（敏感词）④`SAFE_REFUSAL` 兜底。
- **编排** `domain/tutor.py`：`TutorService.explain()` = 输入校验 → `provider.tutor()` → 输出校验；返回 `TutorResult(blocked, reason)`；内部 `asyncio.run` 驱动 async provider（与 `Grader` 一致）。
- **数据**：`TutorLog` 表（child_id 外键 + index）、`create_tutor_log` / `count_tutor_today`（UTC 日期，`func.date`）/ `list_tutor_logs`。
- **路由** `routes/tutor.py`：`POST /tutor/ask`（require_child + 每日上限 429）、`GET /tutor/logs`（require_parent + 越权 403）。
- **前端** `features/tutor/`：`tutor_notifier`（对话 + 日志）、`tutor_chat_screen`（娃娃答疑页，防重入 `_submitting` + 本地 `_sending` 禁用发送、错误保留历史气泡）；`child_home` 问 AI 入口；`parent_dashboard` AI 答疑日志区块。

## 代码审查修复（general-purpose agent）
1. 安全绕过：`check_input` 仅校验 `question` → 改为对 `question+knowledge_point+context` 统一校验。
2. 时区 bug：`count_tutor_today` / `get_child_tasks_today` 用本地 `date.today()` 比 UTC 存储，边界差 8h → 改 `datetime.now(UTC).date()`。
3. 前端防重入 + 错误保留：加 `_submitting` 守卫与本地 `_sending` 禁用；错误时保留历史气泡并附重试提示（移除 `TutorError` 状态）。

## 测试
- 后端：`tests/domain/test_safety.py`（锁/输入/输出）、`tests/domain/test_tutor.py`（编排：正常/输入拦截未调模型/输出拦截）、`tests/api/routes/test_tutor.py`（娃娃提问落日志/越狱拦截/每日上限 429/家长查日志/越权 403/非娃娃 403）。全量 63 passed + 1 skipped，ruff 全过。
- 前端：`test/tutor_notifier_test.dart`（ask body 契约/错误保留/防重入/日志解析）。`flutter analyze` 0 问题、`flutter test` 12→13 passed。

## 提交
见 `git log`（feat(backend+frontend): T08 ...）。
