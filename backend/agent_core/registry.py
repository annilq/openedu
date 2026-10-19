"""agent_core SubAgent 注册表（发现即注册，业务无关）。

每个 subagent 以文件夹 ``<business>/`` 组织，内含：
- ``agent.py``     SubAgent 执行体（``BaseSubAgent`` 子类，由发现自动拾取）
- ``manifest.py`` ``MANIFEST`` 字典：business / name / roles / triggers / hints / priority / skills
- ``skills/``      本 subagent 的提示词/方法论资产（.md，注入 system prompt）

运行时经 ``discover_subagent_manifests(root)`` 扫描文件夹自动注册，新增 subagent = 丢一个文件夹
（无需在任何注册表里手工登记）。路由相关字段（triggers/hints/priority）语义由 ``router`` 解释，
本模块只负责发现 + 业务键 → 类 的查询。
"""
from __future__ import annotations

import importlib
import inspect
import re
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
    # 可见角色：teacher / student（runtime 按当前角色过滤）
    roles: list[str] = field(default_factory=lambda: ["teacher", "student"])
    # 意图触发词（规则匹配用，priority 降序）
    triggers: list[str] = field(default_factory=list)
    # 启发式兜底词（规则未命中时用）
    hints: list[str] = field(default_factory=list)
    # 正则触发词：(已编译正则, 回传的**规范触发词**)。
    #
    # 为什么需要它：``triggers`` 是**子串包含**匹配，「出几道」命不中「出2道」
    # （数字一变就漏），而用户写「出 2 道 / 出一道 / 来三题」远比写「出几道」多。
    # 逐个词穷举数字与量词会指数膨胀，故把「出 + 数词 + 道」这类**族**用正则表达。
    #
    # 回传的必须是 ``triggers`` 里已有的**规范词**（不是正则本身）：下游子意图分组
    # （``intent_schemas[*].triggers``）按词等值判定，回个正则串就永远落不进任何组。
    # 该不变量由契约测试守住。
    trigger_patterns: list[tuple[re.Pattern[str], str]] = field(default_factory=list)
    # 路由优先级：大者先匹配；最小者兼作最终兜底业务
    priority: int = 0
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
        roles=list(data.get("roles", ["teacher", "student"])),
        triggers=list(data.get("triggers", [])),
        hints=list(data.get("hints", [])),
        priority=int(data.get("priority", 0)),
        actions=list(data.get("actions", [])),
        skills=list(data.get("skills", [])),
        trigger_patterns=_compile_trigger_patterns(business, data),
        raw=data,
    )


def _compile_trigger_patterns(
    business: str, data: dict[str, Any]
) -> list[tuple[re.Pattern[str], str]]:
    """``trigger_patterns``（``[{pattern, trigger}]``）→ 已编译正则 + 规范触发词。

    宽容解析：非 list / 缺字段 / 正则编译失败 → 跳过该条并打印告警，不阻断发现——
    静默跳过会让「新加的正则没生效」变成一个查不出来的坑。
    """
    out: list[tuple[re.Pattern[str], str]] = []
    raw = data.get("trigger_patterns")
    if not isinstance(raw, list):
        return out
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        pattern = entry.get("pattern")
        trigger = entry.get("trigger")
        if not pattern or not trigger:
            print(f"[agent_core] subagent {business}: trigger_patterns 条目缺 pattern/trigger，已跳过")
            continue
        try:
            out.append((re.compile(str(pattern)), str(trigger)))
        except re.error as exc:
            print(f"[agent_core] subagent {business}: trigger_patterns 正则非法（{exc}），已跳过")
    return out


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
