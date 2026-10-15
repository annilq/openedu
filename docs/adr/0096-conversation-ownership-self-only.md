# ADR-0096 会话归属收敛为「本人可见」

- 状态：已实现
- 日期：2026-10-15
- 关联：ADR-0048（助手会话历史，**§3 / §6 第三条 / 后果第 1 条被本 ADR 取代**）、ADR-0033（工具出参按角色剥答案）、ADR-0088（admin 复用 teacher 面）、ADR-0022（Conversation / Message）；分层不变量 9（归属只许 `core.guard`）

## 1. 背景

ADR-0048 把「教师可查看学生在问什么」当成特性做进会话列表：归属口径是 `Conversation.teacher_id`，
而学生的会话 `teacher_id` 填的也是教师，于是教师名下同时挂着「自己聊的」与「名下所有学生聊的」。
这个选择带来三笔代价，都在当时的文档里记着：

1. **点击行为分叉**：`student_id IS NULL` 的条目可续接，学生的只能只读回放
   （`assistant_chat_page.dart` 的 `_AssistantMode.reading` + 行上「只读」徽标）。理由是硬性的——
   教师发请求时 `student_id` 恒为 `None`，拿学生的 `session_id` 续接必然过不了归属校验，
   后端会**另建一段会话**并把新 id 回写，屏幕上却像续上了，还会把学生的消息当成教师的 prompt
   历史灌进去。
2. **学生端被有意留空**：没有 student-scoped 列表路由（ADR-0048 §6 第三条）。
3. **判据与用途混在一列上**：`teacher_id` 同时承担「归属」与「教学域」两件事——它还是 RAG 检索
   范围与引擎解析的入参（`service.chat` 的角色分流：学生端 `teacher_id=None` 时资料库回落 mock）。

本 ADR 按新诉求反转：

> 老师不能看学生的会话，每个人都只能看自己的会话——这样就可以编辑了，也不用做只读控制。

「不用做只读控制」是这次反转真正的收益：代价 1 整条分支（只读态、只读徽标、底栏说明、
`isMine` 判别）连同它存在的前提一起消失。

## 2. 决策

### 2.1 归属口径：本人可见，判据收口 `core.guard`

```python
def conversation_owner_clause(user: User):
    if user.role == Role.STUDENT:
        return Conversation.student_id == user.id
    return and_(
        Conversation.teacher_id == user.id,
        Conversation.student_id.is_(None),
    )
```

- 学生：`student_id == 本人`；
- 教师 / admin：`teacher_id == 本人 AND student_id IS NULL`。

判据**只有这一份**，三个消费者都从它取：

| 消费者 | 入口 |
| --- | --- |
| 列表（SQL 过滤） | `repository.list_my_conversations` → `conversation_owner_clause(user)` |
| 详情（单行断言） | `guard.require_owned_conversation(session, user, conv_id)` |
| 删除（批量过滤） | `guard.owned_conversation_ids(session, user, ids)` |

否则「列表能列出、详情 403 / 删除删不掉」这种口径分裂是迟早的事。

### 2.2 `teacher_id` 列不动：教学域 ≠ 归属

学生的会话仍把 `teacher_id` 填为其教师——它表示**这条会话发生在谁的教学域下**（RAG 检索范围、
引擎解析），与本 ADR 的归属是两件事。因此**不引入 `owner_user_id` 列**：多一个「谁拥有」的列
与 `teacher_id` 并列，只会把刚分开的语义重新混回去，还要付迁移 + 双写的成本。

### 2.3 三个端点改双端通用

`GET /conversations`、`GET /conversations/{id}`、`DELETE /conversations` 的依赖从
`CurrentTeacher` 改为 `CallerDep`（与 `/assistant/chat`、`/suggested-actions` 同一口径）。
学生端第一次有了自己的会话列表——这是 ADR-0048 §6 第三条的反转。

响应契约删掉 `student_id` / `student_name`：列表里每条都是本人可见、都可续接，这两个字段
要么是 `None` 要么就是调用者本人，留着只会诱导前端重新长出「只读 / 可编辑」的分叉。

### 2.4 前端：删掉「只读回放」这一整态

- `assistant_chat_page.dart`：删 `_AssistantMode.reading`、`_replay` 及其滚动控制器、`_ReadOnlyNotice`
  底栏；历史入口不再按 `isTeacher` 分叉（双端都有）。
- `assistant_history_view.dart`：两段式分组（我的 / 按娃分段）改成单段列表，删「只读」徽标。
- `domain/conversation.dart`：删 `studentId` / `studentName` / `isMine`。
- `assistant_notifier.dart`：`resume()` 不再有「只对教师自己的会话开放」的前提。

### 2.5 历史数据：留库，不删

已存在的学生会话只是**查不到**，不做物理清理。可逆——将来要恢复教师视角，不必找回数据。

## 3. 后果

- **教师失去「看学生在问什么」的能力**。这条需求应回到 F-305「AI 答疑记录」承担（它的粒度是
  **交换**：一问一答 + 学科标签 + 已拦截徽标），而不是在会话列表里另造入口——ADR-0048 的
  Considered Options 3 当时就是这么写的，只是选择了「包含」。
- **学生能看到自己问过什么**，代价是 ADR-0048 担心的「看到自己被拦过的记录是负面强化」。
  本 ADR 接受这个代价：气泡投影本就不带安全标记（ADR-0048 §6 第二条），回放里没有「已拦截」
  这回事，被拦记录只出现在 TutorLog / F-305。
- **admin 只看自己的**：admin 复用 teacher 面（ADR-0088），走 `teacher_id == me` 分支。
  审计与排障不受影响——`/ai/debug/conversations` 走 `require_owned_or_admin`，是另一个消费者。
- **教师拿学生 `session_id` 去续接**的老问题从「必须靠前端只读来防」变成「根本拿不到」：
  列表不返回、详情 403。即便 id 泄漏，`service.chat` 里 `existing.student_id == student_id`
  的续接校验仍在。

## Considered Options

1. **新增 `owner_user_id` 显式列**（对齐题库 owner-based 归属）：语义直白，但需数据迁移 +
   建会话时双写，且会与 `teacher_id`（教学域）并列，把刚分开的两件事重新混回去。拒绝。
2. **只在前端隐藏学生的会话，后端不改**：按 id 直接打详情仍能拿到，是**假隔离**。归属必须
   在服务端判（分层不变量 9）。拒绝。
3. **物理清理历史学生会话**：教师端立刻干净，但不可逆，且学生自己回看的权利一并被删掉。拒绝。
4. **保留 `student_id` / `student_name` 响应字段**：空壳字段会诱导前端重新长出只读分叉，
   与「端到端彻底删除优于保留空壳」相悖。删除。
