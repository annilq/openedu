"""分层不变量守护测试（ADR-0032 决策 7）。

内核 / 适配器 / 集成三层此前只靠人工 grep 核查，属「靠纪律」而非「靠机制」。
本文件把 4 条不变量固化为 AST 级断言，让越界在 CI 上直接红：

1. ``agent_core`` 内核（不含 ``adapters/``）**零 ``app.*`` 依赖**；
2. ``agent_core`` 内核**零第三方依赖**（只允许 stdlib + 自身）；
3. 全后端 ``import genkit`` **只出现在 ``agent_core/adapters/genkit.py``**，且只在函数体内（延迟导入）；
4. 已删模块（``app.ai.generation`` / ``parsers`` / ``segment`` / ``debug_log`` / ``tools``）**零残留引用**；
5. ``app/features/*/service.py`` **不得 import 本 feature 或其他 feature 的 router**——service 是
   router 与查询工具共用的下游（ADR-0033 决策 13），反向依赖会立刻形成循环；
6. ``app/features/*/service.py`` **不得 import ``fastapi``**——否则查询工具经 service 就绑上了
   HTTP 层（工具在 SSE 请求内同步直调 service，不经 ASGI）；
7. ``app/ai/subagents/query/tools/**`` **不得 import 任何 router 或 repository**——查询工具只许
   经 feature service 取数（ADR-0033 决策 13）；绕过 service 直连 repository 会让聚合逻辑出现
   第二份，正是本次重构要消灭的漂移源。

全部为静态扫描，不打模型、不启服务。
"""
from __future__ import annotations

import ast
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[2]
KERNEL_ROOT = BACKEND_ROOT / "agent_core"
ADAPTER_PATH = KERNEL_ROOT / "adapters" / "genkit.py"
FEATURES_ROOT = BACKEND_ROOT / "app" / "features"
QUERY_TOOLS_ROOT = BACKEND_ROOT / "app" / "ai" / "subagents" / "query" / "tools"

# genkit 是引擎 SDK，其（及插件包）的唯一合法落点是适配器
GENKIT_ROOTS = {"genkit", "genkit_ollama", "genkit_openai", "genkit_fastapi"}
# ADR-0032 已删除的模块，任何 import 都是回归
DEAD_MODULES = {
    "app.ai.generation",
    "app.ai.parsers",
    "app.ai.segment",
    "app.ai.debug_log",
    # ADR-0033：shared_tool 包随 tasks 一并退役（list_tasks 逻辑并入 query 工具、
    # search_knowledge 零调用方）；将来真被复用时再按 ADR-0024 语义重建。
    "app.ai.tools",
}
_SKIP_DIRS = {".venv", "dist", "build", "__pycache__", "site-packages", "htmlcov"}


def _iter_py(root: Path):
    """遍历 root 下的源码文件，跳过虚拟环境 / 构建产物。"""
    for path in sorted(root.rglob("*.py")):
        if _SKIP_DIRS & set(path.parts):
            continue
        yield path


def _import_roots(path: Path, *, top_level_only: bool = False) -> set[str]:
    """AST 级取「顶层模块名」集合（忽略 docstring / 注释中的字面量）。"""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    nodes = tree.body if top_level_only else ast.walk(tree)
    roots: set[str] = set()
    for node in nodes:
        if isinstance(node, ast.Import):
            roots.update(a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            roots.add(node.module.split(".")[0])
    return roots


def _dotted_targets(path: Path) -> set[str]:
    """AST 级取完整点号模块名（含 ``import a.b.c`` 与 ``from a.b import c`` 的 ``a.b``）。"""
    tree = ast.parse(path.read_text(encoding="utf-8"))
    targets: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            targets.update(a.name for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            targets.add(node.module)
            targets.add(f"{node.module}.{node.names[0].name}")
    return targets


def _kernel_files():
    return [p for p in _iter_py(KERNEL_ROOT) if "adapters" not in p.relative_to(KERNEL_ROOT).parts]


def test_kernel_has_no_app_dependency():
    """不变量 1：内核不得反向依赖集成层（依赖方向 app → adapters → kernel）。"""
    offenders = {
        f"{p.relative_to(BACKEND_ROOT)}: {m}"
        for p in _kernel_files()
        for m in _import_roots(p)
        if m == "app"
    }
    assert not offenders, f"agent_core 内核不得 import app.*：{sorted(offenders)}"


def test_kernel_has_no_third_party_dependency():
    """不变量 2：内核零第三方依赖——未装任何 SDK 也能 import 内核。"""
    offenders = {
        f"{p.relative_to(BACKEND_ROOT)}: {m}"
        for p in _kernel_files()
        for m in _import_roots(p)
        if m != "agent_core" and m not in sys.stdlib_module_names
    }
    assert not offenders, f"agent_core 内核只允许 stdlib：{sorted(offenders)}"


def test_genkit_import_only_in_adapter():
    """不变量 3a：genkit SDK 全后端唯一落点是适配器模块。"""
    offenders = {
        str(p.relative_to(BACKEND_ROOT))
        for p in _iter_py(BACKEND_ROOT)
        if _import_roots(p) & GENKIT_ROOTS and p != ADAPTER_PATH
    }
    assert not offenders, f"genkit 只允许在 adapters/genkit.py 内导入：{sorted(offenders)}"


def test_genkit_is_never_imported_at_module_level():
    """不变量 3b：连适配器自身也不许模块级 import genkit（否则未装 genkit 即 ImportError）。"""
    offenders = {
        str(p.relative_to(BACKEND_ROOT))
        for p in _iter_py(BACKEND_ROOT)
        if _import_roots(p, top_level_only=True) & GENKIT_ROOTS
    }
    assert not offenders, f"genkit 必须延迟导入（函数体内）：{sorted(offenders)}"


def test_no_reference_to_deleted_ai_modules():
    """不变量 4：ADR-0032 删除的模块不得被任何源码重新引用。"""
    offenders = {
        f"{p.relative_to(BACKEND_ROOT)}: {m}"
        for p in _iter_py(BACKEND_ROOT)
        for m in _dotted_targets(p)
        if m in DEAD_MODULES or any(m.startswith(f"{d}.") for d in DEAD_MODULES)
    }
    assert not offenders, f"已删模块仍被引用：{sorted(offenders)}"


def _feature_services() -> list[Path]:
    return sorted(FEATURES_ROOT.glob("*/service.py"))


def test_feature_services_do_not_import_routers():
    """不变量 5：feature service 不得依赖任何 router（依赖方向 router → service）。"""
    offenders = {
        f"{p.relative_to(BACKEND_ROOT)}: {m}"
        for p in _feature_services()
        for m in _dotted_targets(p)
        if m.endswith(".router")
    }
    assert not offenders, f"feature service 不得 import router：{sorted(offenders)}"


def test_feature_services_do_not_import_fastapi():
    """不变量 6：feature service 不绑 HTTP 层（查询工具直调，不走 ASGI/依赖注入）。"""
    offenders = {
        f"{p.relative_to(BACKEND_ROOT)}: {m}"
        for p in _feature_services()
        for m in _import_roots(p)
        if m == "fastapi"
    }
    assert not offenders, f"feature service 不得 import fastapi：{sorted(offenders)}"


def _query_tool_files() -> list[Path]:
    return sorted(QUERY_TOOLS_ROOT.rglob("*.py"))


def test_query_tools_go_through_feature_services_only():
    """不变量 7：查询工具只许经 feature service 取数，不得碰 router / repository。

    - 碰 router：依赖方向反了（router → service ← tool）；
    - 碰 repository：聚合与裁剪逻辑会绕过 service 出现第二份（ADR-0033 决策 13）。
    """
    offenders = {
        f"{p.relative_to(BACKEND_ROOT)}: {m}"
        for p in _query_tool_files()
        for m in _dotted_targets(p)
        if m.endswith(".router") or m.endswith(".repository")
    }
    assert not offenders, f"query 工具不得 import router/repository：{sorted(offenders)}"


def test_query_tools_do_not_import_fastapi():
    """不变量 8：查询工具不绑 HTTP 层（handler 在 SSE 请求内同步直调）。"""
    offenders = {
        f"{p.relative_to(BACKEND_ROOT)}: {m}"
        for p in _query_tool_files()
        for m in _import_roots(p)
        if m == "fastapi"
    }
    assert not offenders, f"query 工具不得 import fastapi：{sorted(offenders)}"
