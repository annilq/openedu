"""agent_core SubAgent 注册表（发现即注册，业务无关）。

每个 subagent 以文件夹 ``<business>/`` 组织，内含：
- ``agent.py``     SubAgent 执行体（``BaseSubAgent`` 子类，由发现自动拾取）
- ``manifest.py`` ``MANIFEST`` 字典：business / name / description / roles / priority /
  actions / skills / input_schema / fallback_guide / routing_criteria（后两者为可选路由字段）
- ``skills/``      本 subagent 的提示词/方法论资产（.md，注入 system prompt）

运行时经 ``discover_subagent_manifests(root)`` 扫描文件夹自动注册，新增 subagent = 丢一个文件夹
（无需在任何注册表里手工登记）。路由相关字段（roles / priority / actions）语义由 ``runtime``
解释，本模块只负责发现 + 业务键 → 类 的查询。
"""
from __future__ import annotations

import importlib
import inspect
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, TypeVar

from agent_core.subagent import BaseSubAgent

_T = TypeVar("_T", bound=BaseSubAgent)


@dataclass
class SubAgentManifest:
    """单个 subagent 的声明式元数据（来自 <business>/manifest.py + 同目录资产）。"""

    business: str
    name: str
    description: str = ""
    # 路由专用能力描述（ADR-0106）：缺省为空 → 路由用 ``name`` + ``description`` 的投影。
    # 声明后**只**替换投影里的 description 部分，``name`` / ``actions`` 仍在；面向用户的
    # 能力清单（``capability_catalog``）始终读 ``description``，不受本字段影响。
    # 存在的理由：同一份文本要同时服务「用户读得懂」与「模型分得开」时，实测证明会互相
    # 拖累（ticket 12：把「管理题库」这句留给用户的代价是路由 74% → 56%）。
    routing_criteria: str = ""
    # 可见角色：teacher / student（runtime 按当前角色过滤）
    roles: list[str] = field(default_factory=lambda: ["teacher", "student"])
    # 路由优先级：不再参与「触发词排序竞争」（规则路由已移除，ADR-0104）——
    # 现仅两处语义：① 能力清单（capability subagent）的呈现顺序；② 无任何业务声明
    # ``fallback_guide`` 时的最后防线（数值最小者接住）。新增业务无需再斟酌「抢词」。
    priority: int = 0
    # 无命中引导（ADR-0105）：策略原语（决策模型 / LLM 分类）均不决策时，由本业务
    # 接住并给出「自身能力引导」，而不是静默把消息塞给某个执行体。至多一个业务声明
    # （契约测试守护）；对当前角色不可见时退到 priority 最小者。
    fallback_guide: bool = False
    # 结构化动作键清单（等值匹配，先于触发词；「哪个业务拥有哪个动作」的唯一声明处）。
    # 动作直配不参与优先级排序，因此无需为它设计排序规则（唯一性由契约测试保证）。
    actions: list[str] = field(default_factory=list)
    # 本 subagent 引用的 skill（skills/ 下的 .md 文件名，不含扩展名）
    skills: list[str] = field(default_factory=list)
    # skills/*.md 全文拼接（按声明顺序），发现时读取，运行时注入 prompt
    skill_prompt: str = ""
    # 发现即注册：同目录 agent.py 内定义的 BaseSubAgent 子类
    agent_cls: type[_T] | None = None
    # 原始 dict，便于扩展
    raw: dict[str, Any] = field(default_factory=dict)


def _load_agent_cls(folder_name: str, module_base: str) -> type[BaseSubAgent] | None:
    """从 ``<folder>/agent.py`` 拾取该模块内定义的 ``BaseSubAgent`` 子类。"""
    from agent_core.subagent import BaseSubAgent as _Base

    module_name = f"{module_base}.{folder_name}.agent"
    try:
        mod = importlib.import_module(module_name)
    except Exception as exc:  # noqa: BLE001 — 单个 agent 导入失败不应阻断整体发现
        print(f"[agent_core] subagent {folder_name}: agent 导入失败 {exc}")
        return None
    for _, obj in inspect.getmembers(mod, inspect.isclass):
        if (
            issubclass(obj, _Base)
            and obj is not _Base
            and obj.__module__ == module_name
        ):
            return obj
    return None


def _load_skill_prompt(folder: Path, names: list[str]) -> str:
    """读取 skills/*.md 全文；声明了却缺文件时打印告警。"""
    parts: list[str] = []
    for name in names:
        path = folder / "skills" / f"{name}.md"
        if not path.exists():
            print(f"[agent_core] subagent {folder.name}: skill 缺失 {name}.md")
            continue
        parts.append(path.read_text(encoding="utf-8").strip())
    return "\n\n".join(p for p in parts if p)


def _manifest_from_dict(business: str, data: dict[str, Any]) -> SubAgentManifest:
    return SubAgentManifest(
        business=business,
        name=str(data.get("name", business)),
        description=str(data.get("description", "")),
        routing_criteria=str(data.get("routing_criteria", "")),
        roles=list(data.get("roles", ["teacher", "student"])),
        priority=int(data.get("priority", 0)),
        fallback_guide=bool(data.get("fallback_guide", False)),
        actions=list(data.get("actions", [])),
        skills=list(data.get("skills", [])),
        raw=data,
    )


def discover_subagent_manifests(
    root: Path | None = None, *, module_base: str = "app.ai.subagents"
) -> dict[str, SubAgentManifest]:
    """扫描 subagents 目录下所有含 ``manifest.py`` 的文件夹，返回 business → 清单。

    ``root`` 为 subagent 文件夹的父目录（默认 ``app/ai/subagents`` 同级的约定目录；
    业务工程应传入自己的 subagent 根）。``module_base`` 为这些文件夹的 Python 导入基路径
    （默认 ``app.ai.subagents``），用于定位 ``<folder>.agent`` 模块。

    失败（缺字段/导入异常）的文件夹被跳过并打印告警，不阻断整体发现。
    """
    if root is None:
        # 约定：与 agent_core 包平级的 app.ai.subagents；业务工程应显式传入自己的根。
        root = Path(__file__).resolve().parent.parent / "app" / "ai" / "subagents"
    found: dict[str, SubAgentManifest] = {}
    if not Path(root).exists():
        return found
    for folder in sorted(
        p for p in Path(root).iterdir() if p.is_dir() and not p.name.startswith("_")
    ):
        manifest_py = folder / "manifest.py"
        if not manifest_py.exists():
            continue
        module_name = f"{module_base}.{folder.name}.manifest"
        try:
            mod = importlib.import_module(module_name)
            raw = getattr(mod, "MANIFEST", None)
            if not isinstance(raw, dict):
                continue
            business = str(raw.get("business", folder.name))
            manifest = _manifest_from_dict(business, raw)
        except Exception as exc:  # noqa: BLE001 — 单文件夹失败不应阻断整体发现
            print(f"[agent_core] skip subagent {folder.name}: {exc}")
            continue
        manifest.agent_cls = _load_agent_cls(folder.name, module_base)
        manifest.skill_prompt = _load_skill_prompt(folder, manifest.skills)
        found[business] = manifest
    return found


def get_subagent_class(manifests: dict[str, SubAgentManifest], business: str) -> type[BaseSubAgent] | None:
    """业务键 → SubAgent 类；未知业务返回 None（调用方决定兜底）。"""
    m = manifests.get(business)
    if m is None:
        return None
    return m.agent_cls


def build_subagent(
    manifests: dict[str, SubAgentManifest],
    business: str,
    *,
    provider,
    retriever=None,
) -> BaseSubAgent | None:
    """业务键 → SubAgent 实例；未知业务返回 None（调用方决定兜底）。"""
    agent_cls = get_subagent_class(manifests, business)
    if agent_cls is None:
        return None
    return agent_cls(provider=provider, retriever=retriever)
