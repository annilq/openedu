# T02 — TutorSubAgent 停止伪造 `tutor_explain` 工具帧（候选 1）

**What to build:** `TutorSubAgent.run` 会 emit 一个 `tutor_explain` 的 TOOL_CALL / TOOL_RESULT 帧（`agent.py:112-113` 与 `:145`），但它从不注册 `tutor_explain` 这个 ToolSpec、不进入真实 tool loop，也没有任何调用方/测试/前端依赖该帧名。这个帧是「戏服」：读代码与运行轨迹会误以为走过了一道工具接缝。保留 SubAgent 作为「帧编排层」（它确实做流式讲解 + 交互演示 + 溯源），但去掉这个伪工具帧——要么彻底不发该 TOOL_CALL，要么发一个诚实的步骤标签（明确不是工具）。

**Blocked by:** 无
**Status:** ready-for-agent

## 决策锚点

- **SubAgent 类本身保值**（通过删除测试）：删掉它，复杂度不在调用方重现（唯一调用方是 `AgentRuntime`），所以外壳要留；只有 `tutor_explain` 伪帧要去掉。
- 不要为了「看起来对称」而凭空注册一个 `tutor_explain` ToolSpec——那会把伪造变成真实负债，与去冗余方向相反。
- 若前端/轨迹查看器需要「伴学答疑正在进行」的视觉信号，改用诚实标签（如步骤描述），且名字不得带 `tool` 语义以免再次误导。
- 全仓已确认仅 `docs/adr/0101` 文档示例提过 `tutor_explain`，无测试断言，改名/删除零风险。

## 验收

- [ ] `app/ai/subagents/tutor/agent.py` 不再 emit 名为 `tutor_explain` 的 TOOL_CALL / TOOL_RESULT 帧
- [ ] 事件流仍包含：讲解 delta（ASSISTANT_MESSAGE）、交互演示 DATA 帧（`interactive_scene`）、溯源 DATA 帧（`rag_sources`）——功能等价
- [ ] 若保留步骤标签，其名称不带 `tool`/`_explain` 工具语义，且 `docs/adr/0101` 示例同步更新
- [ ] `tests/ai/` 既有 tutor 用例全绿；新增一个断言「流中不再出现 `tutor_explain` TOOL_CALL」的否定测试
- [ ] `ruff` 改动文件净
