# 架构决策索引 — 娃娃学习 App

> 详文见 [../decisions/娃娃学习App_ADR.md](../decisions/娃娃学习App_ADR.md)（后端 ADR-001..013）与 `frontend/docs/adr/`（前端 ADR-0001..0004）。本页只做速查与关键隔离说明。

## 后端 ADR（节选要点）

| ADR | 决策 |
|---|---|
| 001 | 前端技术选型 Flutter 原生 App，平板优先 |
| 002 | 后端语言 Python |
| 003 | AI 编排用 LangChain + 自封领域接口，**不在 LangChain provider 之上重复封装** |
| 004 | LLM 模型先不定，provider 抽象可插拔（mock / langchain / deepseek） |
| 005 | 数据库 PostgreSQL（SQLite 本地回退） |
| 006 | 本地 Docker 起步，架构按云设计 |
| 007 | 家长管理员 + 娃娃独立账号，数据按娃隔离 |
| 008 | 内容安全双层防护 + 家长可见日志 |
| 009 | 内容来源 AI 生成 + 对齐教材（后期 RAG） |
| 010 | 轻量激励（打卡 streak / 积分 / 徽章） |
| 011 | Pi / Eve 不作为运行时引擎 |
| 012 | 🔴 教材版权合规硬门槛（对外分发前必须解决） |
| 013 | 后端基线 = `fastapi/full-stack-fastapi-template` 二次裁剪（同步 SQLModel、pwdlib+pyjwt、丢弃 React/邮件/Traefik；API 前缀 `/api/v1`；Python 3.14） |
| 0014 | 设计重定向：双模式（家长专业/娃娃活泼）+ 学科色 + 响应式断点 + 适度趣味动效（修订 ADR-0003 单模式） |
| 0015 | 多模型接入（Ollama/自定义）+ 流式响应 + 轻量 GenUI：统一 Genkit 协议（前后端单栈），安全层不降级 |
| 0016 | 合并「生成任务」与「预览出题」为统一「出题」流程（先出题→手动存为任务/加入题库） |
| 0017 | 出题推理流式通道：合并 thinking+typing 为单一 `REASONING` chunk（AG-UI 式 `type` 信封），✅ 已落地 |
| 0018 | 文档目录对齐 ai.md：根目录散落文档归一化到 `docs/` 四类（product/requirements/architecture/decisions） |
| 0019 | 教材版权合规落地方案（上线前内容来源分层 + 公版优先 + 授权路径 + 检索隔离 + CI 检测门禁），操作化 ADR-0012 |
| 0020 | 云部署生产化（无状态镜像 + 托管 PG + 密钥外置 + 边缘 TLS + CI/CD 质量门禁 + 可观测 + 跨设备同步方向） |
| 0021 | 多 Agent 架构：业务 SubAgent（出题/伴学/批改/诊断/规划/报告）+ 学科 Persona 参数注入 + 轻主管派发；首轮双 SubAgent 验证 seam |
| 0024 | Agent Runtime 架构：SubAgent 文件夹化（`app/ai/subagents/<business>/` + manifest）+ `AgentRuntime` 统一发现/加载 + 混合意图路由（规则优先 + LLM 兜底）+ SSE 端点 `POST /api/v1/assistant/chat`；不推翻 ADR-0021 契约 |
| 0025 | 助手交互协议：AG-UI 式统一事件信封（`USER_MESSAGE`/`ASSISTANT_MESSAGE`/`THINKING`/`TOOL_CALL`/`TOOL_RESULT`/`STEP`/`CARD`/`ERROR`/`DONE`），扩展 ADR-0017 为通用聊天协议 |
| 0026 | 双端角色感知派发（强化 ADR-008）+ 助手会话持久化（`AssistantSession`/`AssistantEvent`）；废除 `debug_log`，supersede ADR-0022 |
| 0027 | 后端包结构 Feature-First（模块化单体）：`app/features/<name>/` + ORM 集中 `app/db/models/` + 共享内核 `app/domain`·`app/core` |
| 0028 | 出题改为单调用真流式（推理增量 + 题卡），取代「先整题后打字机」 |
| 0029 | 出题解析与转换四管分层（Decode → Demux → Parse → Translate），解析器只判定不兜底 |
| 0030 | 助手运行时抽象收口：引擎单一解析链（删 `BaseSubAgent.engine` 死参数）+ SubAgent 发现即注册（删 registry 手工登记）+ `skills` 真注入 prompt + 删除未接线的 LLM 分类插槽 |
| 0031 | Agent 抽象层抽取为通用框架 `agent_core`（独立可安装包 + 真实 tool loop + 协议信封自有），升级 ADR-0003 |
| 0032 | `agent_core` 分层边界与命名收敛（ports-and-adapters）：`seams.py`→`ports.py`；genkit 走 `adapters/`（**不进内核**）；出题业务归 `app/ai/subagents/question/`；删除死代码 `debug_log.py` |

## 前端 ADR

| ADR | 决策 |
|---|---|
| 0001 | 抽取共享做题组件（AppQuizResultCard / AppAnswerResultDialog 等） |
| 0002 | 默认中性灰白主题 + 桌面左右分栏壳（替换底部 Tab） |
| 0003 | Linear 化重设计：密排 15sp + 靛蓝强调 + **删除暖绿**；家长专业体验 > 低龄友好 |
| 0004 | Task 多学科 + 题库快照隔离（`draft→ready→assigned→done`；`Question`=题库层；`TaskQuestion`=派发快照） |
| 0006 | 悬浮 AI 助手：全局悬浮按钮 + 对话框入口，`AssistantClient` SSE 调 `POST /api/v1/assistant/chat`，角色感知；复用 tutor 聊天组件 |

## 关键隔离（任何改动都要守住）

- 业务（`api/`、`domain/`）**不直接 import langchain**；换模型 = 改配置，不碰业务代码。
- 娃娃端**永远拿不到标准答案**（`Question.answer` 仅家长端返回）。
- 内容安全：系统层年龄锁 prompt + `check_input` / `check_output` 确定性校验，命中返回 `SAFE_REFUSAL` 并记 `tutor_log.blocked`，**不向娃娃暴露拒绝原因**。
- `TaskQuestion` 派发冻结：家长编辑草稿 / 题库不污染已派发任务。

## 后端架构文档导航（唯一事实源）

- **[../architecture/技术架构_后端.md](../architecture/技术架构_后端.md)** — 后端架构**唯一事实源**。由原《技术架构_后端.md》与《项目分析_架构规范与业务功能.md》合并精简而来（2026-09-09），已校正至 Feature-First 架构（ADR-0027）：`app/features/<name>/` 每能力一目录、ORM 表集中 `app/db/models/`、AI 统一入口 `/assistant/chat`。业务功能（F-101~F-306）、开发规范、技术债均并入该文。
