"""T05 回归护网：features 下原 AI 调试 REST 包已重命名为 ``app.features.agent_debug``。

纯重命名、零行为变化。URL 前缀 ``/ai/debug`` 由 ``router.py`` 的 ``APIRouter(prefix="/ai")``
固定，与包名无关，故契约不变。本测试只断言 import 路径层已完成迁移、无残留旧名。

扫描范围仅限 ``backend/app/``，避免本测试文件自身的字面量干扰计数。
"""

import re
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent / "app"


def _count(substr: str) -> int:
    """Count regex matches of ``substr`` across ``app/`` (``.`` matches any char,

    mirroring ``grep`` so slashed docstring paths like ``app/features/...`` are
    counted the same as dotted import paths).
    """
    total = 0
    for path in APP_ROOT.rglob("*.py"):
        text = path.read_text(encoding="utf-8")
        total += len(re.findall(substr, text))
    return total


def test_old_features_ai_import_gone():
    """旧包名 ``app.features.ai`` 在 backend/app 中不应再出现。"""
    assert _count("app.features.ai") == 0


def test_new_features_agent_debug_import_count():
    """新包名 ``app.features.agent_debug`` 在 backend/app 中至少命中 6 处：

    - ``app/api/main.py`` 挂载 import（1）
    - 包内自引：``masking.py``（1）+ ``router.py``（3）
    - ``app/features/assistant/schemas.py`` 文档字符串指向的重命名后路径（1）

    用 ``>= 6`` 而非 ``== 6``：将来新增合法引用不应让本迁移护网假失败。
    """
    assert _count("app.features.agent_debug") >= 6
