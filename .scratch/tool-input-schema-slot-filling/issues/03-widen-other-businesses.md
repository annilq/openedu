# 03: 拓宽切片 — query / tutor / guide 接入预检

**What to build:** 把 01 验证过的同一套预检引擎接到其余业务（query / tutor / guide），使这些业务的槽位也走统一的抽取与（必要的）澄清；读操作与问答不过度追问。capability 无输入、不变。本票让"每个工具都有 input schema 且缺参被处理"从出题扩展到全业务。

**Blocked by:** 01（引擎与契约已证明）

**Status:** ready-for-agent

- [ ] query（6 个 optional 槽）接入预检：缺可选槽不阻塞，直接回答；subject/grade/kp 等从消息/context 抽取、可推断则声明。
- [ ] tutor（question_text required + 3 optional）接入：缺 `question_text` → 澄清（它是唯一必填）；subject/grade/knowledge_point 可选、从 context 透传。
- [ ] guide（3 optional）接入：仅做导航，不代写，不阻塞。
- [ ] capability 确认无输入、返回固定清单，行为不变。
- [ ] 各业务抽取 + 非阻塞行为有测试；最小阻塞纪律落地（只 tutor 的 question_text 为必填，query/guide 全 optional 不追问）。

## 纪律 / 实施提示
- 复用 01 的 `slot_filling` 引擎，不重写抽取逻辑；各 business 的 `input_schema` 已在 00 落地。
- 守住最小阻塞：读操作（query）与问答（tutor/guide）过度追问反而干扰，故仅 tutor 的 `question_text` 设为必填追问。
- 不引入新事件类型；澄清帧契约与 01/02 一致（`extra.clarify`）。
