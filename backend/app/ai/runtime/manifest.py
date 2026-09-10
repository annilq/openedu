"""SubAgent 清单（文件化结构，ADR-0024；发现即注册，ADR-0030）。

每个 subagent 以文件夹 ``app/ai/subagents/<business>/`` 组织，内含：
- ``agent.py``      SubAgent 执行体（``BaseSubAgent`` 子类，由发现自动拾取）
- ``manifest.py``  ``MANIFEST`` 字典：business / name / roles / triggers / hints / priority / tools / skills
- ``tools/``        本 subagent 专用 tool（可执行函数）
- ``skills/``       本 subagent 的提示词/方法论资产（.md，注入 system prompt）

``manifest.py`` 而非 ``.yaml``：避免引入 PyYAML 依赖，且类型安全、可静态检查。
运行时经 ``discover_subagent_manifests()`` 扫描文件夹自动注册，新增 subagent = 丢一个文件夹
（ADR-0030：agent 类与 skills 文本同批发现，无需在任何注册表里手工登记）。

路由相关字段（ADR-0030：从 intent_router 里的硬编码表搬进 manifest）：
- ``triggers``：精准规则词，命中即路由。
- ``hints``：宽松兜底词，规则全未命中时才用。
- ``priority``：匹配优先级，大者先匹配；**最小的那个兼作最终兜底业务**（当前为 tutor）。
"""
from __future__ import annotations

import importlib
import inspect
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class SubAgentManifest:
    """单个 subagent 的声明式元数据（来自 <business>/manifest.py + 同目录资产）。"""

    business: str
    name: str
    description: str = ""
    # 可见角色：parent / child（runtime 按当前角色过滤，ADR-0026）
    roles: list[str] = field(default_factory=lambda: ["parent", "child"])
    # 意图触发词 / 示例短语（规则匹配用，顺序见 priority）
    triggers: list[str] = field(default_factory=list)
    # 启发式兜底词（规则未命中时用，ADR-0030）
    hints: list[str] = field(default_factory=list)
    # 路由优先级：大者先匹配；最小者作最终兜底（ADR-0030）
    priority: int = 0
    # 本 subagent 引用的 skill（skills/ 下的 .md 文件名，不含扩展名）
    skills: list[str] = field(default_factory=list)
    # skills/*.md 全文拼接（按声明顺序），发现时读取，运行时注入 prompt（ADR-0030）
    skill_prompt: str = ""
    # 发现即注册：同目录 agent.py 内定义的 BaseSubAgent 子类（ADR-0030）
    agent_cls: type | None = None
    # 原始 dict，便于扩展
    raw: dict[str, Any] = field(default_factory=dict)


_SUBAGENTS_DIR = Path(__file__).resolve().parent.parent / "subagents"


def _load_agent_cls(folder_name: str) -> type | None:
    """从 ``<folder>/agent.py`` 拾取该模块内定义的 ``BaseSubAgent`` 子类。

    惰性导入基类以打破 ``app.ai.subagents`` ↔ ``app.ai.runtime`` 的包初始化期循环依赖。
    只认 ``__module__`` 等于该 agent 模块的子类，避免把 import 进来的基类误判。
    """
    from app.ai.subagents.base import BaseSubAgent

    module_name = f"app.ai.subagents.{folder_name}.agent"
    try:
        mod = importlib.import_module(module_name)
    except Exception as exc:  # noqa: BLE001 — 单个 agent 导入失败不应阻断整体发现
        print(f"[runtime] subagent {folder_name}: agent 导入失败 {exc}")
        return None
    for _, obj in inspect.getmembers(mod, inspect.isclass):
        if (
            issubclass(obj, BaseSubAgent)
            and obj is not BaseSubAgent
            and obj.__module__ == module_name
        ):
            return obj
    return None


def _load_skill_prompt(folder: Path, names: list[str]) -> str:
    """读取 skills/*.md 全文；声明了却缺文件时打印告警（此前是静默丢弃）。"""
    parts: list[str] = []
    for name in names:
        path = folder / "skills" / f"{name}.md"
        if not path.exists():
            print(f"[runtime] subagent {folder.name}: skill 缺失 {name}.md")
            continue
        parts.append(path.read_text(encoding="utf-8").strip())
    return "\n\n".join(p for p in parts if p)


def _manifest_from_dict(business: str, data: dict[str, Any]) -> SubAgentManifest:
    return SubAgentManifest(
        business=business,
        name=str(data.get("name", business)),
        description=str(data.get("description", "")),
        roles=list(data.get("roles", ["parent", "child"])),
        triggers=list(data.get("triggers", [])),
        hints=list(data.get("hints", [])),
        priority=int(data.get("priority", 0)),
        skills=list(data.get("skills", [])),
        raw=data,
    )


def discover_subagent_manifests(root: Path | None = None) -> dict[str, SubAgentManifest]:
    """扫描 subagents 目录下所有含 ``manifest.py`` 的文件夹，返回 business → 清单。

    ADR-0030：清单里同时带上 ``agent_cls``（发现即注册）与 ``skill_prompt``（SOP 文本）。
    失败（缺字段/导入异常）的文件夹被跳过并打印告警，不阻断整体发现。
    """
    root = root or _SUBAGENTS_DIR
    found: dict[str, SubAgentManifest] = {}
    if not root.exists():
        return found
    for folder in sorted(p for p in root.iterdir() if p.is_dir() and not p.name.startswith("_")):
        manifest_py = folder / "manifest.py"
        if not manifest_py.exists():
            continue
        module_name = f"app.ai.subagents.{folder.name}.manifest"
        try:
            mod = importlib.import_module(module_name)
            raw = getattr(mod, "MANIFEST", None)
            if not isinstance(raw, dict):
                continue
            business = str(raw.get("business", folder.name))
            manifest = _manifest_from_dict(business, raw)
        except Exception as exc:  # noqa: BLE001 — 单文件夹失败不应阻断整体发现
            print(f"[runtime] skip subagent {folder.name}: {exc}")
            continue
        manifest.agent_cls = _load_agent_cls(folder.name)
        manifest.skill_prompt = _load_skill_prompt(folder, manifest.skills)
        found[business] = manifest
    return found
