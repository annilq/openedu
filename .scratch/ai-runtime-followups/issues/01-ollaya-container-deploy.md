# 01: 容器化部署补上 `OLLAYA_URL`

> 标签：`done`（2026-10-21）
> 来源对话：2026-10-21 用户「按照 4 个提案优化」提案 1
> 关联：ticket 11（`ai-intent-routing`，本机 ollaya 接入）、ADR-0107（门控上移后决策模型的
> 分数就是路由输入）、ticket 14（主原语选型）

**落地摘要**：`OLLAYA_URL` 此前只存在于 `backend/.env:32`（本地开发），compose 与 Dockerfile
都没设 —— 容器里决策原语恒不可用，每轮路由落 LLM 分类（p50 1084 ms，纯前置、不与流式
重叠）。本票把 ollaya 作为服务加进 compose，并把「**卷里真有模型**」写进健康检查。
真机冷卷验证：2 分钟内 healthy，跨容器（compose 网 `openedu_default`）打 `/v1/systemone`
拿到 `{"choice":"tutor","confidence":0.5301,"probabilities":{...}}`。

## Problem Statement

1. `LayaDecisionModel.available()` 恒为 False（无 `OLLAYA_URL`）→ 路由每轮走 LLM 分类，
   本地 66 ms 变成生产 1084 ms，且那 1 s 是**纯前置等待**（不与正文流式重叠）。
2. 更隐蔽的：`ollaya pull` 必须连服务端。先 `pull` 再 `serve` 时容器照常 healthy、端口也通，
   但模型根本没进卷 —— 一个「看起来一切正常、实际上恒走降级路径」的部署。

## Solution

1. compose 新增 `ollaya` 服务 + `backend` 的 `OLLAYA_URL` / `OLLAYA_MODEL` /
   `AI_ROUTING_STRATEGY` / `depends_on` + `ollaya` 卷。
2. entrypoint 顺序**不可反**：

   ```yaml
   entrypoint:
     - /bin/sh
     - -c
     - >-
       ollaya serve & srv=$!;
       until bash -c 'exec 3<>/dev/tcp/127.0.0.1/11435' 2>/dev/null; do sleep 1; done;
       ollaya pull "$${OLLAYA_MODEL:-laya:multilingual}";
       wait "$${srv}"
   ```

3. 镜像自带健康检查只探端口，挡不住「没模型」这个形态，另加一条：

   ```yaml
   healthcheck:
     test:
       - CMD-SHELL
       - >-
         bash -c 'exec 3<>/dev/tcp/127.0.0.1/11435' 2>/dev/null &&
         ollaya list 2>/dev/null | tail -n +2 | grep -q .
     start_period: 10s
     interval: 5s
     timeout: 10s
     retries: 60
   ```

4. `backend/.env.example` 补 `OLLAYA_URL` / `OLLAYA_MODEL` / `AI_ROUTING_STRATEGY` 三段注释
   （容器化由 compose 注入，本文件供本地开发）。

## Implementation Decisions

- **镜像标签**：默认（CPU）即可跑 amd64/arm64；`:cuda` / `:cuda12` 才需要 NVIDIA 容器工具包。
- **卷挂 `/home/ollaya/.ollaya`**（容器内 `OLLAYA_MODELS=/home/ollaya/.ollaya/models`）。
- 顺序敏感性是本次最重要的发现：**先 serve 再 pull**，且必须等端口真的通了再 pull。
- `AI_ROUTING_STRATEGY` 一并注入，默认 `auto`（决策模型可用则用之）。

## 验证

- 冷卷起容器 → 2 分钟内 `healthy`，`docker exec` 里 `ollaya list` 显示 `laya:multilingual 683 MB`。
- 跨容器实测：网内 `POST http://ollaya:11435/v1/systemone` 拿到结构化决策（含 `probabilities`）。
- 顺带实测到一个佐证：句子「请给我出 5 道二元一次方程的选择题」被决策模型判成
  `tutor`（0.687）、`tasks` 只有 0.294 —— 正是 ticket 13 记录的那类有害错，带动作键的 chip
  （ticket 02）能整条绕开它。
