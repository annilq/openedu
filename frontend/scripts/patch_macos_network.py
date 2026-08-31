#!/usr/bin/env python3
"""幂等地修复 macOS 构建的网络权限。

背景（坑）：`flutter create --platforms=macos .` 或重新生成 macOS 项目时，
会把 `macos/Runner/*.entitlements` 和 `Info.plist` 刷回 Flutter 默认值，
从而抹掉两件事，导致 App 发起的 HTTP 请求在系统层被拦截（后端零日志）：
  1. App Sandbox 的 `com.apple.security.network.client`（出站网络）—— 缺则请求发不出去；
  2. `NSAppTransportSecurity > NSAllowsLocalNetworking` —— 缺则 ATS 拦截明文 HTTP
     （本项目后端是 http://127.0.0.1:8000）。

本脚本用于「重新生成 macOS 后一键恢复」，可反复运行（幂等）。

用法：
    python3 frontend/scripts/patch_macos_network.py
"""
from __future__ import annotations

import os
import plistlib
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RUNNER_DIR = os.path.normpath(os.path.join(HERE, "..", "macos", "Runner"))

ENTITLEMENTS = ["DebugProfile.entitlements", "Release.entitlements"]
# 需要写进每个 entitlements 的键值（缺才补，已存在则保持）
ENTITLEMENT_PATCHES = {
    "com.apple.security.network.client": True,
}

# Info.plist 需要写入的 ATS 例外（覆盖 localhost 与局域网明文 HTTP）
ATS_KEY = "NSAppTransportSecurity"
ATS_VALUE = {"NSAllowsLocalNetworking": True}


def _changed(before: bytes, after: bytes) -> bool:
    return before != after


def patch_entitlements(path: str) -> bool:
    if not os.path.exists(path):
        print(f"  [skip] 不存在: {path}")
        return False
    with open(path, "rb") as f:
        data = f.read()
    with open(path, "rb") as f:
        plist = plistlib.load(f)

    dirty = False
    for k, v in ENTITLEMENT_PATCHES.items():
        if plist.get(k) != v:
            plist[k] = v
            dirty = True
            print(f"  [patch] {os.path.basename(path)}: 设置 {k} = {v}")

    if dirty:
        with open(path, "wb") as f:
            plistlib.dump(plist, f)
    else:
        print(f"  [ok]    {os.path.basename(path)}: 网络权限已就位")
    return dirty


def patch_info_plist(path: str) -> bool:
    if not os.path.exists(path):
        print(f"  [skip] 不存在: {path}")
        return False
    with open(path, "rb") as f:
        plist = plistlib.load(f)

    ats = plist.get(ATS_KEY)
    if isinstance(ats, dict) and ats.get("NSAllowsLocalNetworking") is True:
        print(f"  [ok]    Info.plist: ATS 本地网络例外已就位")
        return False

    if not isinstance(ats, dict):
        ats = {}
    ats["NSAllowsLocalNetworking"] = True
    plist[ATS_KEY] = ats
    with open(path, "wb") as f:
        plistlib.dump(plist, f)
    print(f"  [patch] Info.plist: 写入 {ATS_KEY}.NSAllowsLocalNetworking = true")
    return True


def main() -> int:
    if not os.path.isdir(RUNNER_DIR):
        print(f"[error] 找不到 macOS Runner 目录: {RUNNER_DIR}", file=sys.stderr)
        print("        请在 frontend/ 仓库根目录下运行本脚本。", file=sys.stderr)
        return 1

    print(f"修复 macOS 网络权限: {RUNNER_DIR}")
    changed = False
    for name in ENTITLEMENTS:
        changed |= patch_entitlements(os.path.join(RUNNER_DIR, name))
    changed |= patch_info_plist(os.path.join(RUNNER_DIR, "Info.plist"))

    if changed:
        print("\n[done] 已应用补丁。重新构建 macOS 即可恢复联网：")
        print("       flutter build macos --debug   # 或 flutter run -d macos")
    else:
        print("\n[done] 无需改动，网络权限已满足。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
