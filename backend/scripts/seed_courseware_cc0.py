"""维护期 CLI：入库平台 CC0 预置素材（T08 / ADR-0067 §3.5·§5）。

运行前确保环境变量 ``DATABASE_URL`` 指向目标库（开发 / 部署库），然后：

    python backend/scripts/seed_courseware_cc0.py

幂等：同名 CC0 素材已存在则跳过。图片离线随仓库分发，本脚本不联网。
"""
from __future__ import annotations

import sys
from pathlib import Path

# 让脚本能 import app（仓库根在 backend/）。
_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT))

from sqlmodel import Session  # noqa: E402

from app.core.db import engine  # noqa: E402
from app.features.courseware.seed_cc0 import seed_courseware_cc0  # noqa: E402


def main() -> None:
    with Session(engine) as session:
        n = seed_courseware_cc0(session)
    print(f"CC0 素材入库完成，本次新增 {n} 条。")


if __name__ == "__main__":
    main()
