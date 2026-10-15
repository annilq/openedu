# 工具输入 schema 与缺槽追问 · Tickets 索引

> 来源：ADR-0095（读代码/实施前先看它）。
> **[SPEC.md](SPEC.md)**：本轮可执行 spec（问题/方案/用户故事/实现与测试决策/非目标）。
> 本地 `.scratch`（gh 未认证，未建 GitHub issue）。每张 ticket 含 What to build / Blocked by / Status / 验收；新票统一打 `ready-for-agent` 分诊标。

## 范围

给每一个 AI 工具（subagent 业务）在 manifest 定义 `input_schema`，并在 subagent 生成前插入确定性预检层 `slot_filling`：缺必填槽→产出澄清帧并写回已知槽位、return（不生成）；齐全→先发汇总确认再生成。半成形意图跨轮保存在 `Conversation.slots`，使「持续提醒输入」在多轮里真正成立。最小阻塞：只问 `subject`+`grade`（出题加 `qtype`），其余默认 + 汇总声明。

## 依赖链（to-tickets 垂直重切）

```
00 schema 落地（manifest 写 input_schema）──── done
01 后端垂直（引擎+持久化+question 接线+后端测试）─ done
02 前端垂直（clarify 卡+汇总+前端测试）────────── done
03 拓宽（query/tutor/guide 接入）────────────── done
```

**全部 4 票已合入 `integration/tool-input-schema-slot-filling`**（00→01→02/03 并行）。
本轮收尾时补掉两个实现期才暴露的缺陷，均已在 ticket 内标注：

- `01` 补丁：完整轮必须把 merged 槽位写入 `ctx.extra["specs"]`，否则生成步回落
  自由文本兜底、丢失已收集槽位（「继续生成」承诺失效）；另修正 int 抽取把年级当
  成数量（`grade`/`count` 现按槽名分派）。
- `03` 补丁：`tutor.question_text` 降为可选，否则自由问答恒被追问而阻塞。

- 01 是核心 tracer bullet：跨层（schema→引擎→持久化→API→后端测试）一次打通出题业务的缺槽闭环，无需前端即可经集成测试演示。
- 02 与 03 都只依赖 01，可在 01 后**并行**（02 是 UI 层、03 是其余业务的 widen）。
- 每票都是垂直切片（窄但完整穿过各层、可独立验证），非水平分层。

## 用户决策锚点（grill-with-docs 钉死，勿再开讨论）

| # | 决策 | 出处 |
|---|---|---|
| 1 | 承载单元 = 每个 subagent 在 manifest 声明 `input_schema`，结构化 action 复用，单一事实源 | 用户拍板 |
| 2 | 循环机制 = 确定性预检层（引导用户输入），不靠模型随机发挥 | 用户拍板 |
| 3 | 槽位记忆 = 跨会话持久化（`Conversation.slots`），追问只问缺失项 | 用户拍板 |
| 4 | 追问策略 = 最小阻塞（只阻塞 subject+grade，出题加 qtype） | 用户拍板 |
| 5 | schema 内容 = 铺全字段（question 10 / query 6 / tutor 4 / guide 3 / capability 0） | 用户拍板 |
| 6 | 追问帧契约 = 普通消息 + 标记（`extra.clarify`），不新增 eventType | 用户拍板 |
| 7 | 测试接缝 = 单元层 + 集成层 + 前端层，三档全要 | 用户拍板（to-spec 确认） |
| 8 | 票型 = 垂直 tracer bullet（to-tickets 重切为 3 票：T1 后端 / T2 前端 / T3 拓宽），每票跨层、可独立演示 | 用户拍板（to-tickets 确认） |

## 共同纪律

- `flutter analyze` 0 issue（该命令退出码常非 0，以输出里「No issues found!」为准）；全仓 `flutter test` 无回归。
- 单文件 ≤400 行（ADR-0058，超限抽 part，**不**直接上调基线）。
- 全站禁 Material 控件；可点区一律 `AppFocusableAction`；前端测试**禁截图装置**（无真实合成器会挂死）→ 一律几何/结构断言。
- 后端新增 JSON 列须 `JSON(none_as_null=True)`（ADR-0061）；迁移为加列、幂等 DDL（ADR-0053）。
- 不破坏结构化 `POST /tasks/generate` 路径；澄清帧为普通消息落库，历史回放里是正常的气泡。
- `enum_ref` 引用 `app.domain.subjects.SUBJECTS`（ADR-0055 §11 收敛为 数学/语文/英语），解析为单一权威列表。
