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

## 前端 ADR

| ADR | 决策 |
|---|---|
| 0001 | 抽取共享做题组件（AppQuizResultCard / AppAnswerResultDialog 等） |
| 0002 | 默认中性灰白主题 + 桌面左右分栏壳（替换底部 Tab） |
| 0003 | Linear 化重设计：密排 15sp + 靛蓝强调 + **删除暖绿**；家长专业体验 > 低龄友好 |
| 0004 | Task 多学科 + 题库快照隔离（`draft→ready→assigned→done`；`Question`=题库层；`TaskQuestion`=派发快照） |

## 关键隔离（任何改动都要守住）

- 业务（`api/`、`domain/`）**不直接 import langchain**；换模型 = 改配置，不碰业务代码。
- 娃娃端**永远拿不到标准答案**（`Question.answer` 仅家长端返回）。
- 内容安全：系统层年龄锁 prompt + `check_input` / `check_output` 确定性校验，命中返回 `SAFE_REFUSAL` 并记 `tutor_log.blocked`，**不向娃娃暴露拒绝原因**。
- `TaskQuestion` 派发冻结：家长编辑草稿 / 题库不污染已派发任务。

## 后端架构文档导航（两份，注意重叠）

- **[../architecture/技术架构_后端.md](../architecture/技术架构_后端.md)** — 后端架构**事实源**。已修正 §5.1（provider 为 `async`，非同步）与 §6（Task 状态 `draft→ready→assigned→done`，非 `pending|done`）两处过期描述。
- **[../architecture/项目分析_架构规范与业务功能.md](../architecture/项目分析_架构规范与业务功能.md)** — 业务功能 + 架构规范分析，与《技术架构_后端.md》高度重叠、互补阅读。**架构判断以《技术架构_后端.md》为准**；涉及具体业务功能细节再查本文。
