# Ticket 04 — 端到端回归与文档收口（关闭 ADR-0088 §7）

- **What to build**: 串联 ticket 01/02/03 做端到端回归（后端 `pytest` + 前端 `flutter analyze`/`flutter test`，0 回归）；并把 ADR-0088 §7 三个开放问题关闭或显式记入 Backlog：(a) admin 是否也跨教师看 `tutor_logs` 伴学安全审计；(b) 破窗留痕落库位置；(c) 前端运行轨迹入口形态（独立管理区 vs 历史详情展开）。如决定落地某项，拆子票；如延后，写入 Backlog。最后在 ADR-0088 追加「实施完成」状态段。
- **Blocked by**: 01, 02, 03
- **Status**: done
- **验收清单**:
  - 后端 `ruff check` + `pytest`（沙盒 `--basetemp` 新目录）全绿；前端 `flutter analyze`（认 `No issues found!`）+ `flutter test`（先关代理）0 回归。
  - 归属隔离回归：引入 admin 后教师仍只看自家、学生仍被拒、admin 越界只读不写。
  - usage 回归：落库后抽样 `Message`，`usage`/`latency_ms`/`model` 非空（至少 generation/tool 步）。
  - ADR-0088 §7 三个开放问题各有结论（落定子票 or 记入 Backlog）；ADR-0088 追加实施完成状态段。
  - CONTEXT.md 术语（运行轨迹/管理员/破窗访问）与实现一致，无 stale 描述。

## 决策锚点

- **文档跟着代码走**：ADR-0088 是决策底稿，本票负责把「已做/未做/延后」写清楚，不让 spec 与实现分叉。
- **开放问题不悬空**：§7 三项必须给结论（落定 or Backlog），不留 stale 状态字段。
