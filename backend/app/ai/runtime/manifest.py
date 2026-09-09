"""SubAgent 清单（文件化结构，ADR-0024）。

每个 subagent 以文件夹 ``app/ai/subagents/<business>/`` 组织，内含：
- ``agent.py``      SubAgent 执行体（BaseSubAgent 子类或等价工厂）
- ``manifest.py``  ``MANIFEST`` 字典：business / name / description / roles / triggers / tools / skills
- ``tools/``        本 subagent 专用 tool（可执行函数）
- ``skills/``       本 subagent 的提示词/方法论资产（.md，注入 system prompt）

``manifest.py`` 而非 ``.yaml``：避免引入 PyYAML 依赖，且类型安全、可静态检查。
运行时经 ``discover_subagent_manifests()`` 扫描文件夹自动注册，新增 subagent = 丢一个文件夹。
"""
from __future__ import annotations

import importlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class SubAgentManifest:
    """单个 subagent 的声明式元数据（来自 <business>/manifest.py）。"""

    business: str
    name: str
    description: str = ""
    # 可见角色：parent / child（runtime 按当前角色过滤，ADR-0026）
    roles: list[str] = field(default_factory=lambda: ["parent", "child"])
    # 意图触发词 / 示例短语（意图路由规则匹配用，ADR-0024 混合路由）
    triggers: list[str] = field(default_factory=list)
    # 本 subagent 依赖的 tool（shared_tool 写 app/ai/tools/，专用 tool 写 tools/）
    tools: list[str] = field(default_factory=list)
    # 本 subagent 引用的 skill（skills/ 下的 .md 文件名，不含扩展名）
    skills: list[str] = field(default_factory=list)
    # 原始 dict，便于扩展
    raw: dict[str, Any] = field(default_factory=dict)


_SUBAGENTS_DIR = Path(__file__).resolve().parent.parent / "subagents"


def _manifest_from_dict(business: str, data: dict[str, Any]) -> SubAgentManifest:
    return SubAgentManifest(
        business=business,
        name=str(data.get("name", business)),
        description=str(data.get("description", "")),
        roles=list(data.get("roles", ["parent", "child"])),
        triggers=list(data.get("triggers", [])),
        tools=list(data.get("tools", [])),
        skills=list(data.get("skills", [])),
        raw=data,
    )


def discover_subagent_manifests(root: Path | None = None) -> dict[str, SubAgentManifest]:
    """扫描 subagents 目录下所有含 ``manifest.py`` 的文件夹，返回 business → 清单。

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
            found[business] = _manifest_from_dict(business, raw)
        except Exception as exc:  # noqa: BLE001 — 单文件夹失败不应阻断整体发现
            print(f"[runtime] skip subagent {folder.name}: {exc}")
    return found
