# 03 — 可插拔 LLM 真接通 smoke

**What to build:** 接真实 LangChainProvider（国产模型 OpenAI 兼容端点），验证出题走真实模型且换模型零业务代码改动；工厂按配置选择实现（mock/langchain）。

**Blocked by:** 01 — 测试基座：闭环 pytest 套件

**Status:** ready-for-agent

- [x] `LLM_PROVIDER=langchain` 时，`QuestionGenerator` 经真实模型出题，业务代码无改动
- [x] 在 `.env` 切换 `base_url`/`model` 即可换厂商，无需改业务层（故事 12）
- [x] 真实出题结果结构与 `GeneratedQuestion` 契约一致（`subject, grade, knowledge_point, qtype, stem, options, answer, explanation, difficulty`）
- [x] Provider 工厂单测覆盖选择逻辑（mock 默认、langchain 显式、未知值回退）

---

**完成情况（2026-08-20）：**

- 依赖：`pyproject.toml` 新增 `langchain-openai`（OpenAI 兼容端点覆盖国产模型，换厂商只需改 `base_url`/`model`）
- 工厂：`app/domain/__init__.py:build_provider` 对未知 `LLM_PROVIDER` 值告警并回退 mock，服务始终可启动
- 单测（15 passed，1 skipped）：
  - `tests/domain/test_provider_factory.py` — mock 默认 / langchain 显式 / 未知值回退 / langchain 缺配置报错
  - `tests/domain/test_langchain_provider.py` — `_build_model` 从 settings 接线 base_url/model/api_key；`generate_question` 契约字段齐全；`_parse_json` 容错（markdown 围栏/尾随文本/垃圾输入）
  - `tests/domain/test_llm_smoke.py` — 真实模型 smoke（`-m smoke`，需 `LLM_PROVIDER=langchain` + key + `RUN_LLM_SMOKE=1`，默认 skip）
- 配置样例：根 `.env.example` 与 `backend/.env.example` 同步为当前 SQLModel 实现，补充 smoke 运行说明
- 顺手修复既有 lint：`ruff check --fix` 清理 import 排序/未用 import（deps.py、auth.py、tasks.py、models.py、user.py），并删除 `test_loop.py` 未用变量

**真实模型验证命令：**

```bash
cd backend
LLM_PROVIDER=langchain LLM_API_KEY=sk-xxx LLM_BASE_URL=https://api.hunyuan.cloud.tencent.com/v1 LLM_MODEL=hunyuan-lite RUN_LLM_SMOKE=1 uv run pytest tests/domain/test_llm_smoke.py -m smoke -v
```
