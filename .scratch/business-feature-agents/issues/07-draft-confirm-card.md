# 07 · 前端草稿确认卡 + 卡片渲染

## What to build

- DATA 帧新卡片种类 `task_draft_card`：渲染器按 `data.type` 分派（ADR-0042 既有机制），展示草稿摘要（标题/科目/年级/题数/目标学生）+ 「确认发布」/「取消」按钮。
- 按钮动作：**直走 REST** `POST /tasks/{id}/confirm` + `POST /tasks/{id}/assign`（前端已有调用代码，复用）；成功后卡片转「已发布」态或Toast。不新造 AI 确认动作键。
- 禁 Material 纪律：按钮用 `AppFocusableAction` / ShadButton，不用 InkWell。
- 卡片文件 ≤400 行；`ai_text_fold` / 渲染分派处接线。

## Blocked by

04（帧契约）。

## 验收

- widget 测试：`task_draft_card` 帧渲染出摘要与两按钮；点「确认发布」触发 confirm+assign REST 调用（fake repository 断言入参）。
- 回放（ADR-0095 补全后）里草稿卡同样可渲染（气泡投影白名单不带 card 语义——task_draft_card 是 DATA 帧落库的 cards，走既有 cards 通道，天然可回放；验收确认这条链路）。
