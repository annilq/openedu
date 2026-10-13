# 遗留兼容性设计清理（未上线，可大胆删）

> 来源 spec：本次代码审计（`CODE_AUDIT_REPORT.md` 的 P0/P1/P2）与 `feature_relationship_tree.html`。
> 术语以 `CONTEXT.md` 为准。范围 = 拆 home↔courseware 依赖环（P0）、移除 ADR-0044 视觉迁移残留 + 双密钥回退（P1）、收尾 Resource 半迁移 + 导航三元组 + subagent 越权依赖（P2）。
> 项目未上线 → 兼容性壳可以整段删，不做保留式迁移。

一句话：**把"为了不破坏旧用法而留的壳"全部拆掉，让每个概念只有一个真身。**

## Tickets（依赖序，blockers first）

| ID | 标题 | 类型 | Blocked by | Status |
|----|------|------|-----------|--------|
| 01 | 把 CoursewareRecentBar 搬进 courseware 特性 | P0 环·半 | — | done |
| 02 | 把 KnowledgePointSceneEditor 搬进 shared 中性层 | P0 环·半 | — | done |
| 03 | home_notifier 改经 assistant provider 层 | P0 层违规 | — | done |
| 04 | 验证 P0 依赖环已消失 | P0 收口 | 01, 02, 03 | done |
| 05 | 迁移遗留 M3 视觉令牌（42 文件） | P1 宽重构·migrate | — | done |
| 06 | 删除 app_theme 兼容令牌块 | P1 宽重构·contract | 05 | done |
| 07 | 移除 crypto 双密钥回退 | P1 后端 | — | done |
| 08 | 完成 Resource<T> 加载态迁移 | P2 宽重构 | — | in_progress |
| 09 | 折叠 home 导航三元组为 sealed 单源 | P2 前端 | — | ready-for-agent |
| 10 | 停止 scene_intent 直连 assistant.repository | P2 后端 | — | ready-for-agent |

**Frontier（无 blocker，可立即抓）：** 08, 09, 10（01–07 已 done）。
**被阻塞：** 无（04、06 已 done）。

## 决策锚点（写进每张 ticket）

- **兼容性壳 = 技术债，不是功能**：凡标"兼容，新代码勿用"的令牌 / 回退分支，删除即收益，不存在"谁还在用"的保留理由——扫描到就迁、迁完就删。
- **单源真身**：一个设计令牌只有一个名字、一个密钥只有一个来源、一个取数状态只有一个泛型、一个导航状态只有一个 sealed 真源。
- **删之前先迁**：先改消费者再删壳，删完用 grep 闸门确认零引用（`flutter analyze` + 定向 grep）。
- **未上线 → 不保留开关**：不要为"万一旧调用方还在"留 feature flag；扫描零命中即硬删。
- **密钥回退是安全隐患**：`SECRET_KEY` 兜底会让"本应加密的 api_key"在没配 `MODEL_APIKEY_SECRET` 时落到 `SECRET_KEY` 派生密钥，属静默降安全级，必须去掉。

## 测试缝

- **P0 视觉无关**：靠 `flutter analyze` + 定向 grep（`features/courseware` 内无 `features/home` import）守门。
- **01 密钥**：单元测 `_fernet()`——有 `MODEL_APIKEY_SECRET` 出密钥、无则按环境（DEV 警告+明文 / 非 DEV 启动失败）；`decrypt` 解不开仍只返 `None`（ADR-0038 不变）。
- **02 Resource**：每屏只断言"取数四态渲染正确"，不碰内部；迁移后旧 sealed 加载态类引用归零。
- **02 导航**：断言"激活页只由 sealed 状态决定"，`_showProfile` 布尔在代码中不存在。
- **02 scene_intent**：断言 `scene_intent.py` 不再 import `features.assistant.repository`，改为依赖中性端口/服务。

## 转 GitHub issue 步骤（待登录）

1. `gh auth login`（或设 `GH_TOKEN`）
2. 按依赖序建 issue，`Blocked by` 指向对应编号
3. 全部打 `ready-for-agent` 标签

建 issue 命令模板：
`gh issue create --title "LCC-<NN> — <标题>" --body-file .scratch/legacy-compat-cleanup/issues/<NN>-<slug>.md --label ready-for-agent`
