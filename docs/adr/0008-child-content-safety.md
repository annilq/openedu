# 儿童内容安全：儿童双层防护与硬门槛

儿童内容安全是产品的硬门槛（双层防护），由工具侧契约测试 + 输入安全闸门双重守护，而非靠人工 review。儿童端构造专属的 `ChildSafety` 实例注入运行时，家长端不放行；越狱/非学习类输入在进入模型前即被拦截。

- **双层防护零改动注入**：儿童端输入安全闸门 `ChildSafety` 把确定性 `check_input` 适配为 agent_core 的 `Safety` 抽象，既有的儿童双层防护（ADR-008）零改动注入运行时，且「仅儿童端构造此实例」（家长端不拦截）（`backend/app/domain/safety.py:78`、`:82`）。
- **端点角色感知 + 输入安全**：悬浮助手统一端点对娃娃端做角色感知与输入安全（ADR-008），家长端可出题/查任务/伴学（`backend/app/features/assistant/router.py:8`）。
- **娃娃端绝不输出答案**：学情查询 SOP 明确娃娃端绝不输出题目答案与解析，也不引导其索要答案（`backend/app/ai/subagents/query/skills/query_sop.md:21`）。
- **安全标记入表**：`Message` 落 `input_safe / output_safe / blocked` 标记，调试可定位被拦步骤（`backend/app/db/models/conversation.py:44`、`:56-58`）。
- **工具侧契约硬门槛**：出题/查询工具契约测试把「娃娃端无答案」作为硬门槛守护——遍历全部工具跑一遍娃娃视角，断言输出中不含答案与解析（`backend/tests/ai/test_query_tools_contract.py:7,244`）。
- **越狱/非学习输入防御层**：端到端测试断言越狱/非学习类输入在首层输入安全拦截、返回 ERROR 帧；娃娃正常伴学答疑落 TutorLog（ADR-008 / F-305）（`backend/tests/api/routes/test_assistant.py:84`、`:65`）。
- **输入安全闸门首层防御**：运行时 `decide` 对娃娃端不安全输入短路，`business is None`、`INPUT_UNSAFE` 错误码收尾（`backend/tests/ai/test_agent_runtime.py:96`、`:97`）。

**Considered Options**：① 仅靠 prompt 层约束（易被越狱绕过，拒绝）；② 确定性规则 + 工具契约测试双闸（采用）。

**Consequences**：安全靠测试契约与输入闸门守住，不依赖人工 review；儿童双层防护对运行时零侵入。代价是新增儿童相关能力须同步补充契约测试，否则 CI 不拦截。
