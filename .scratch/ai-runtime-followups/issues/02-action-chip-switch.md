# 02: 动作直配做成会话内显式切换出口

> 标签：`done`（2026-10-21）
> 来源对话：2026-10-21 用户「按照 4 个提案优化」提案 2
> 关联：ADR-0081（动作直配 = 等值匹配，恒在路由最前）、ADR-0104（规则路由移除后动作是唯一的
> 确定性路由）、ADR-0107（门控上移：文本路由会低分没入引导）

**落地摘要**：后端目录里 4 条出题类入口补上 `action="task_generate"`，前端 chip 点击走
`onAction(payload, action)` 把动作键连同文本一起发出。后端 `AssistantChatReq.action` 早就
存在（只差前端没传）——这次补的是**出口**，不是新的路由机制。抽查显示「请给我出 5 道二元
一次方程的选择题」被决策模型判成 `tutor`（0.687），带动作键的 chip 能整条绕过门控。

## Problem Statement

1. 动作直配是唯一不受门控影响的路由路径，但它只有**结构化来源**（课件练习方向 / 待判定态
   方向 / 客户端结构化动作）在用；用户在会话里点「出几道题练练」这类建议 chip 时，那句文本
   还要再过一遍文本路由，于是**门控会把它没入能力引导**——明明是确定性意图，却走最不确定的路。
2. 表现：chip 上的文案本身就是系统给的，用户点了它却被判成「不知道归谁」。

## Solution

1. `SuggestedAction` 新增可选 `action`（值必须落在某个 manifest 的 `actions` 里）。
2. 出题类入口声明 `action="task_generate"`：
   `_FOLLOWUP_BY_BUSINESS["tasks"]` 的「再出几道」「降低难度」、
   `_FOLLOWUP_BY_BUSINESS["capability"]` 的「出几道题练练」、
   `_KP_FOLLOWUP` 与 `_build_empty_suggested_actions` 的「出一道判断题」。
   讲题 / 查数据类是纯导航或纯文本，**不带动作**（不是什么都要挂）。
3. 前端：chip 点击 → `onAction(payload, action)` → `send(..., action: a)`，后端同一条
   `AssistantChatReq` 接收，动作直配在最前命中，不参与门控。

## Implementation Decisions

- **用独立的 `onAction` 回调而不是给 `onPrompt` 加命名参数**：Dart 不从上下文推断闭包的
  命名参数，`void Function(String, {String? action})` 会让所有 `(_) {}` 字面量编译失败
  （本次 10 处测试 + 1 处 `assistant_summary_card.dart:60` 报错，全部回退后才想通）。
  四个 widget 的 `onPrompt` 一律保持 `void Function(String)`。
- 契约测试守护「目录声明的动作键必须真在 `discover_subagent_manifests()` 的 `actions` 里」——
  防止动作名与清单不同步时**静默退回文本路由**（那正是本票要修的缺陷形态）。

## 验证

- 后端 `tests/features/assistant` + `tests/api/routes/test_assistant.py`：**102 passed**。
- 前端 `flutter analyze`：全仓 "No issues found!"。
- 反向收益：`assistant_chat_page.dart` 因抽出 `_sendPrompt`（消掉两处长 lambda）从 578 行
  压到 **549 行**，低于 ADR-0058 棘轮基线。
