"""内置模型服务商目录（优化模型管理：简化家长手动输入，票据 08）。

家长在「添加模型」时无需逐项手抄 provider / base_url / 模型名：
- 选一个服务商预设（如 deepseek）即可自动带出 provider 与默认 base_url；
- models 列表给出该服务商常见模型名建议，前端渲染下拉/快捷选择，也可自由输入。

目录结构集中维护，新增服务商只需在此追加一条。
条目字段：
- key        目录键（用于 create/update 的 provider_preset）
- label      展示名
- provider   引擎类型：ollama | openai_compat（与 ModelConfig.provider 对齐）
- base_url   默认端点（openai_compat 必填；ollama 缺省走 settings.OLLAMA_BASE_URL）
- models     该服务商常见模型名建议
- api_key_hint / doc_url  辅助提示（仅前端展示用）

⚠️ 维护须知：各厂商模型迭代很快，models 列表需不定期按官方文档刷新
（base_url 一般长期稳定，但模型名/推荐别名会随版本变化）。最近一次
核对：2026-08-31，依据各厂商官方 API 文档。
"""
from __future__ import annotations

from typing import Any

# 注意：base_url 与文档链接可能随时间调整，集中维护于此一处。
BUILTIN_PROVIDERS: dict[str, dict[str, Any]] = {
    "deepseek": {
        "key": "deepseek",
        "label": "DeepSeek",
        "provider": "openai_compat",
        "base_url": "https://api.deepseek.com",
        # 2026-08 起 DeepSeek 取消 deepseek-chat / deepseek-reasoner，统一为 V4 系列：
        # - v4-flash / v4-pro 为通用对话模型（调用别名会自动指向最新小版本，如 -0731/-0813）；
        # - v4-flash-vision-exp 为实验性多模态（支持图片输入）。
        # 推理能力不再靠单独的 reasoner 模型，而是在请求里开 thinking 参数（见 api-docs）。
        "models": [
            "deepseek-v4-flash",
            "deepseek-v4-pro",
            "deepseek-v4-flash-vision-exp",
        ],
        "api_key_hint": "sk-...（platform.deepseek.com）",
        "doc_url": "https://api-docs.deepseek.com/zh-cn/",
    },
    "openai": {
        "key": "openai",
        "label": "OpenAI",
        "provider": "openai_compat",
        "base_url": "https://api.openai.com/v1",
        # 2026-08 官方主力：GPT-5.x 系列 + 4.1 非推理旗舰 + o3/o4-mini 推理模型。
        # 已移除已淘汰的 gpt-4-turbo / o1 / o1-mini / gpt-4o（属 2024 旧代）。
        "models": [
            "gpt-5.2",
            "gpt-5-mini",
            "gpt-4.1",
            "gpt-4.1-mini",
            "o3",
            "o4-mini",
        ],
        "api_key_hint": "sk-...（platform.openai.com）",
        "doc_url": "https://platform.openai.com/docs/models",
    },
    "moonshot": {
        "key": "moonshot",
        "label": "Kimi（月之暗面）",
        "provider": "openai_compat",
        "base_url": "https://api.moonshot.cn/v1",
        # 已移除第一代 moonshot-v1-8k/32k/128k；现行 Kimi K2 系列：
        # - kimi-k2.6 默认即思考（推理）模型，支持视觉+文本+Agent；
        # - kimi-k2.5 支持视觉/思考/对话；kimi-k2-turbo-preview 高性价比；kimi-k2.7-code 编程向。
        "models": [
            "kimi-k2.6",
            "kimi-k2.5",
            "kimi-k2-turbo-preview",
            "kimi-k2.7-code",
        ],
        "api_key_hint": "sk-...（platform.moonshot.cn）",
        "doc_url": "https://platform.moonshot.cn/docs/api/chat",
    },
    "qwen": {
        "key": "qwen",
        "label": "通义千问（阿里云百炼）",
        "provider": "openai_compat",
        "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        # qwen-plus / qwen-max / qwen-turbo 为百炼长期维护的友好别名（仍可用）；
        # qwen3-max / qwen3-coder-plus 为 Qwen3 代次的具体模型。已移除 qwen2.5-72b-instruct（Qwen2.5 旧代）。
        "models": [
            "qwen-plus",
            "qwen-max",
            "qwen-turbo",
            "qwen3-max",
            "qwen3-coder-plus",
        ],
        "api_key_hint": "sk-...（dashscope.aliyuncs.com）",
        "doc_url": "https://help.aliyun.com/zh/model-studio",
    },
    "zhipu": {
        "key": "zhipu",
        "label": "智谱 GLM",
        "provider": "openai_compat",
        "base_url": "https://open.bigmodel.cn/api/paas/v4",
        # 现行主力：GLM-5.3 旗舰 + GLM-5.3-Flash 多模态/高性价比；GLM-4.5 / 4.5-Air 为稳定代次；
        # GLM-4-Flash 长期免费档。已移除 glm-4-plus / glm-4-air（GLM-4 旧代别名）。
        "models": [
            "glm-5.3",
            "glm-5.3-flash",
            "glm-4.5",
            "glm-4.5-air",
            "glm-4-flash",
        ],
        "api_key_hint": "id.secret（open.bigmodel.cn）",
        "doc_url": "https://open.bigmodel.cn",
    },
    "doubao": {
        "key": "doubao",
        "label": "豆包（火山方舟）",
        "provider": "openai_compat",
        "base_url": "https://ark.cn-beijing.volces.com/api/v3",
        # 现行主力：Doubao-Seed-1.6 及其 thinking/flash 变体；1.5-pro-32k 为上一稳定代次；
        # doubao-pro-32k 仍可用（旧代通用模型）。已移除 doubao-lite-4k（旧代精简档）。
        "models": [
            "doubao-seed-1.6",
            "doubao-seed-1.6-thinking",
            "doubao-seed-1.6-flash",
            "doubao-1.5-pro-32k",
            "doubao-pro-32k",
        ],
        "api_key_hint": "sk-...（console.volcengine.com）",
        "doc_url": "https://console.volcengine.com/ark",
    },
    "ollama": {
        "key": "ollama",
        "label": "Ollama（本地）",
        "provider": "ollama",
        "base_url": "http://localhost:11434",
        # 本地模型标签随 Ollama 库更新；下列为常用且仍有效的标签（家长也可自由输入任意本地标签）。
        "models": ["llama3.3", "qwen2.5", "qwen3", "deepseek-r1", "phi3"],
        "api_key_hint": "本地运行，一般无需密钥",
        "doc_url": "https://ollama.com",
    },
}

# 前端下拉展示顺序（语义化排序，ollama 置底作为本地选项）
_PROVIDER_ORDER = ["deepseek", "openai", "moonshot", "qwen", "zhipu", "doubao", "ollama"]


def list_provider_presets() -> list[dict[str, Any]]:
    """返回服务商目录（按固定顺序），供前端渲染下拉与模型名建议。"""
    ordered = [BUILTIN_PROVIDERS[k] for k in _PROVIDER_ORDER if k in BUILTIN_PROVIDERS]
    # 防御性：追加任何未在顺序表中列出的条目
    seen = set(_PROVIDER_ORDER)
    ordered.extend(v for k, v in BUILTIN_PROVIDERS.items() if k not in seen)
    return ordered


def get_provider_preset(key: str) -> dict[str, Any] | None:
    """按 key 取服务商预设；不存在返回 None。"""
    return BUILTIN_PROVIDERS.get(key)
