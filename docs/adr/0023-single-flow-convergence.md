# 单流收口：出题写库只经 /tasks/from-generated

出题业务的落库只保留一处写点——前端把流式端点已生成的题卡 POST 到 `POST /tasks/from-generated` 建草稿任务（两步法第二步）；整卷/单题重生成复用共享出题核心按 `Task.model` 重跑，不再另起写库路径或依赖已删除的 batch-generate。

- **唯一业务写库点**：测试统一以「已生成题卡」直接落库，`/tasks/from-generated` 是出题唯一业务写库点（ADR-0023）（`backend/tests/api/routes/test_review.py:33`、`test_wrong_questions.py:25`、`test_mastery.py:32`、`test_loop.py:30`）。
- **端点落点**：`POST /from-generated` 在 tasks router 中仅做 HTTP 适配，转交 service（`backend/app/features/tasks/router.py:55`、`:60`）。
- **落库实现**：`tasks_service.create_from_generated` 只做归属/非空校验并构造 TaskQuestion 草稿，不重新调用出题引擎（`backend/app/features/tasks/service.py:564`、`:580`、`:618`）。
- **重生成复用共享核心**：整卷重生成按 `Task.model` 经 `resolve_engine` 解析引擎后走共享出题管线 `pipeline.stream_question`，同步/流式版共用同一落库函数 `_commit_regenerated`（`backend/app/features/tasks/service.py:858`、`:866`、`:251`）。
- **回归守护**：整卷重生成「尊重所选模型」回归测试，验证所选 `model` 经 resolve_engine 实际驱动出题而非 mock（`backend/tests/api/routes/test_batch_generate_model.py:1`、`:7`、`:104`、`:108`）。

**Considered Options**：① 保留 batch-generate 生成期自写库分叉（双写路径漂移，拒绝）；② 单流收口 + 重生成复用共享出题核心（采用）。

**Consequences**：出题写库路径唯一、可审计；重生成与首生成共享同一条 Prompt/引擎链，所选模型在重生成时生效；已删除的 batch-generate 严禁复活（分层不变量拦截）。
