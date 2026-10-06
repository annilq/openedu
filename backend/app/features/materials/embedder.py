"""embedding 客户端（ADR-0055 §7/§8）：服务端基础设施，不进教师 ModelConfig。

只提供 **dense** 向量：BGE-M3 的 sparse 输出需要本地权重文件（不进镜像），
检索侧的 sparse 通道改为**查询时词法现算**（见 ``retrieval.py``）——单教师
数千片段的量级下，这比维护一套稀疏索引更便宜，效果等价（BM25 同族）。
"""

from __future__ import annotations

import httpx

from app.core.config import settings

# 每批送端点的文本数：教材切片普遍 <1KB，16 片一批对 ollama / openai 都安全
_BATCH_SIZE = 16


class EmbeddingUnavailableError(RuntimeError):
    """embedding 服务未配置或调用失败（向量化端点据此落 failed 态）。"""


def embedding_configured() -> bool:
    return settings.EMBEDDING_PROVIDER != "none"


def _base_url() -> str:
    base = settings.EMBEDDING_BASE_URL.strip()
    if base:
        return base.rstrip("/")
    if settings.EMBEDDING_PROVIDER == "ollama":
        return settings.OLLAMA_BASE_URL.rstrip("/")
    raise EmbeddingUnavailableError("EMBEDDING_BASE_URL 未配置")


async def embed_texts(texts: list[str]) -> list[list[float]]:
    """批量向量化；返回与输入等长的向量列表。失败抛 EmbeddingUnavailableError。"""
    if not embedding_configured():
        raise EmbeddingUnavailableError(
            "未启用向量化服务（EMBEDDING_PROVIDER=none），请在服务端配置 embedding 模型"
        )
    vectors: list[list[float]] = []
    async with httpx.AsyncClient(timeout=settings.EMBEDDING_TIMEOUT_S) as client:
        for i in range(0, len(texts), _BATCH_SIZE):
            batch = texts[i : i + _BATCH_SIZE]
            vectors.extend(await _embed_batch(client, batch))
    return vectors


async def _embed_batch(
    client: httpx.AsyncClient, batch: list[str]
) -> list[list[float]]:
    if settings.EMBEDDING_PROVIDER == "ollama":
        url = f"{_base_url()}/api/embed"
        payload = {"model": settings.EMBEDDING_MODEL, "input": batch}
        resp_key = "embeddings"
    else:  # openai_compat
        url = f"{_base_url()}/embeddings"
        payload = {"model": settings.EMBEDDING_MODEL, "input": batch}
        resp_key = ""  # data[].embedding
    headers = (
        {"Authorization": f"Bearer {settings.EMBEDDING_API_KEY}"}
        if settings.EMBEDDING_API_KEY
        else {}
    )
    try:
        resp = await client.post(url, json=payload, headers=headers)
        resp.raise_for_status()
        body = resp.json()
    except (httpx.HTTPError, ValueError) as e:
        raise EmbeddingUnavailableError(f"embedding 服务调用失败：{e}") from e
    if resp_key:
        out = body.get(resp_key)
        if not isinstance(out, list) or len(out) != len(batch):
            raise EmbeddingUnavailableError("embedding 响应格式不符合预期")
        return out
    data = body.get("data")
    if not isinstance(data, list) or len(data) != len(batch):
        raise EmbeddingUnavailableError("embedding 响应格式不符合预期")
    return [item["embedding"] for item in data]
