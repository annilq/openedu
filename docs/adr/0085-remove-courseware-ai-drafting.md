# ADR-0085 移除课件 AI 起草，课件内容改为纯手动编排

- 状态：已采纳（已实现）
- 日期：2026-10-11
- 关联：ADR-0067（教师端课件 · 知识点驱动；本 ADR 反转其 §3.4「AI 起草 + 教师调」的取舍）、ADR-0078（课件模块一等化；本 ADR 把其 §2.5「AI 降为辅助」进一步降为**零 AI**，保留 §2.4「手动添加环节」）、ADR-0066（空课件纪律，仍有效）、ADR-0084（同批次的服务端能力删减）
- **Supersede**：ADR-0067 §3.4 的「AI 起草整份课件」与 ADR-0078 §2.5 的「AI 补充讲解」两条能力被删除。**不动**其余结论：课件仍是一等模块、仍按知识点快照建、环节仍是统一内容块容器、手动增删改序照旧。
- 依赖：无（纯删减）。

## 1. 背景（Context）

### 1.1 课件里有两处彼此独立的 AI

| 处 | 能力 | 端点 / 触发点 |
|---|---|---|
| **A** | AI 生成**课件内容**（起草 / 补充讲解 / 重新起草） | `POST /courseware`（`draft=true`）与 `POST /courseware/{id}/redraft`；前端「AI 补充讲解 / AI 重新起草」按钮 |
| **B** | 讲课现场的**助手集成**（问 AI 老师、课堂练习出题与答错分级提示） | `POST /assistant/chat` 带课件上下文；动作键 `courseware_generate` / `courseware_hint` / `quiz_judge` |

本 ADR 只处理 **A**。B 是助手能力在课件场景的使用，**保留不动**（见 §3）。

### 1.2 A 的边际价值已很低

- 课件本就由教师按知识点备课，环节内容（提问话术 / 素材 / 场景 / 练习）**全部来自教师的选择**，AI 起草只是把这些选择先猜一遍、再让教师逐段审。ADR-0078 把新建改成「先建空壳、再按需 AI 补充」，已经等于承认「AI 不该是唯一作者」。
- 为 A 付出的成本不低：一条 `build_ai_provider` 调用链 + 一套「未配模型 / 厂商拒绝 / 产出解析失败」的失败分类 + 「老师点的素材 id 白名单」防编造收敛 + 一整块逐段 diff（`compute_section_diff` / `_section_match_key` / `_segment_signature` / `_same_section_content`）与重起草弹窗。
- ADR-0078 §2.4 落地后，**手动添加环节**这条路径已完备：新建空课件 → 「添加环节」→ 配提问 / 素材 / 场景 / 练习 → `PUT /sections` 整体覆盖写。A 不再是「没有替代」的能力。

### 1.3 `draft` 参数已是历史包袱

前端两处调用（课件中心「新增课件」、编辑器 `_createFirst`）**都已经传 `draft: false`**，即现实中从不触发 AI 起草——服务端那条 `draft=True` 分支只剩测试在用。

## 2. 决策（Decision）

### 2.1 删除 A 的全链（前后端）

**后端**
- 端点：`POST /courseware/{courseware_id}/redraft`。
- 服务（`courseware/service.py`）：`draft_sections` / `_collect_draft` / `_sections_from_draft` / `_DraftSection` / `_CoursewareDraft` / `_DRAFT_SYSTEM`，及其专属前置 `_recall_snippets` / `_retriever` / `_candidate_assets` / `_candidate_scenes` 与 prompt 预算常量。
- 逐段 diff 组（只服务重起草）：`compute_section_diff` / `redraft_diff` / `_section_match_key` / `_segment_signature` / `_same_section_content`。
- 契约（`courseware/schemas.py`）：`SectionDiffItem` / `CoursewareRedraftDiff`；`CoursewareCreate.draft` 字段一并删除（见 2.2）。
- 随之无用的 import（`build_ai_provider` / `run_async` / `ProviderRequestError` / `StructuredDone` / `warnings` / `defaultdict` / `json`）。

**前端**
- 删除 `courseware_redraft_diff.dart`（模型）、`courseware_redraft_dialog.dart`（逐段预览弹窗）。
- `courseware_repository(.impl).dart`：删 `getRedraftDiff` 端口与实现，`createCourseware` 去掉 `draft` 参数。
- `courseware_editor_page.dart`：删 `_redraft()` 与「AI 补充讲解 / AI 重新起草」按钮。
- 文案：编辑器 / 课件中心 / 新建表单 / 演示页空态中「用 AI 起草」「AI 补充讲解」的指引改为「手动添加环节」。

### 2.2 新建恒为**零环节空课壳**

`create_courseware` 去掉 `draft` 分支，只按知识点快照建一份空课件（`sections=None`，零环节）。后端**不再需要模型配置**，因此也不再有 `LLM_UNAVAILABLE` / `LLM_REQUEST_FAILED` 这一失败面。`objective`（教学目标 / 备注）仍落库，供课件信息卡展示。

### 2.3 明确保留的部分

- **B：讲课现场的助手集成**（`courseware_generate` / `courseware_hint` / `quiz_judge`、`AssistantChatReq.courseware` 通道、`SectionPractice` 的出题与答错分级提示、演示页「问 AI 老师」）——本 ADR 不触碰。
- **手动编排全链**：`POST /courseware`（建空课件）、`PUT /sections`（整体覆盖写）、`PATCH /{id}`（标题 / 状态）、`DELETE /{id}`、素材库端点。
- **`Task`/课件以外的既有 AI 出题**（`/tasks/generate` 等）不受影响。
- `payload` 字段与前端对它的回退读取（历史数据兼容）保留。

## 3. 后果（Consequences）

- `courseware/service.py` 从 ~740 行降到 ~300 行；课件域不再依赖 `build_ai_provider`，新建课件不再可能因模型配置失败。
- 课件内容 100% 由教师决定，与「教师按知识点备课」的产品定位一致；代价是全新课件需要教师自己写第一个环节（此前可由 AI 起草一份再改）。
- **文档债清偿**：ADR-0067 §3.4、ADR-0078 §2.5 的 AI 能力由本 ADR 追认；ADR 只读不重写，旧文不回改。
- 契约守护：后端用例 `test_redraft_endpoint_is_gone` 钉住 `POST /redraft` 返回 404；`test_create_*` 钉住新建产空课件且不调模型。
- ⚠️ 与 B 的边界：删的是「服务端生成课件内容」，不是「课件场景里用 AI」。后来者若要再删 B，应另开 ADR。

## 4. 备选（Considered Options）

- **保留 AI 起草、只删「重新起草」**：起草与重新起草共用同一条 `draft_sections` 与同一套 diff，拆开留一半仍要养整套失败分类与防编造收敛，收益不成比例。否决。
- **把 AI 起草搬进 `/assistant/chat` 的结构化动作**：把死代码换个地方，还扩大 chat 的动作面，且与「课件内容由教师编排」的定位无关。否决。
- **保留端点、仅标注 dead code**：正是这种「看着还活着」诱发了 ADR-0084 的删除，标注不足以阻止误用。否决。
