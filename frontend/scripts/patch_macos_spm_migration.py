#!/usr/bin/env python3
"""把 macOS 工程从 CocoaPods 迁移到 SwiftPM（Flutter 3.44+ 的默认）。

背景：
Flutter 3.44 起默认启用 Swift Package Manager。`flutter run -d macos` 会检查工程里
的插件是否都已能用 SwiftPM 提供；若全部可以、但工程仍带 CocoaPods 集成，就打印
一段迁移指引（pod deintegrate / 删 Podfile / 移除两个 xcconfig 里的 include）并且
**每次构建都提示**。此时 CocoaPods 已是纯负债：`macos/Pods/` 里只剩骨架
（Pods.xcodeproj、Target Support Files），一个插件都没有——插件都走 SPM 了。

为什么必须脚本化：`macos/` 在 `.gitignore` 里（平台目录不进版本控制），所以这些
改动换机器、或 `flutter create` 重建平台目录后就会回来，且**没有任何 git 痕迹**。
与 `patch_voice_permissions.py` / `patch_spm_cwl_mirror.py` 同一对策。

要清的五处（缺一处就还会提示，或更糟：构建时找不到 Pods）：

  macos/Podfile                                      删
  macos/Pods/                                        deintegrate 会删
  macos/Flutter/Flutter-Debug.xcconfig               去掉 Pods-Runner.debug include
  macos/Flutter/Flutter-Release.xcconfig             去掉 Pods-Runner.release include
  macos/Runner.xcodeproj/project.pbxproj             去掉 ~31 处 CocoaPods 引用
  macos/Runner.xcworkspace/contents.xcworkspacedata  去掉对 Pods.xcodeproj 的 FileRef

⚠️ 最后两行里的 pbxproj 只能靠 `pod deintegrate`：里面是 build phase（`[CP] Check Pods
Manifest.lock`）、xcconfig 引用、`Pods.xcodeproj` 引用等交织的结构，手工正则改 Xcode
工程文件极容易改出一个打不开的工程。所以脚本里 pod 不可用时会**报错退出**，而不是
假装迁移成功。

⚠️ `pod deintegrate` 收尾会打印「Note: The workspace referencing the Pods project still
remains」——它**不管** `Runner.xcworkspace/contents.xcworkspacedata`，那里留着一条
`location = "group:Pods/Pods.xcodeproj"`，而 Pods/ 已删。xcodebuild 走的是
`-workspace Runner.xcworkspace`，吊着一条指向不存在工程的引用不是好事，所以脚本自己
补上这一步。

用法：
    python3 frontend/scripts/patch_macos_spm_migration.py          # 迁移（幂等，可反复跑）
    python3 frontend/scripts/patch_macos_spm_migration.py --check  # 只检查不写入；未迁移则退出码 1

⚠️ 前置：SwiftPM 必须能解析依赖。若插件里有远程 Swift 包（本项目是
`speech_to_text` → `CwlCatchException`），先跑 `patch_spm_cwl_mirror.py`。
本脚本只做「摘掉 CocoaPods」，不解决依赖解析。
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FRONTEND = os.path.normpath(os.path.join(HERE, ".."))
MACOS = os.path.join(FRONTEND, "macos")

PBXPROJ = os.path.join(MACOS, "Runner.xcodeproj", "project.pbxproj")
WORKSPACE_DATA = os.path.join(MACOS, "Runner.xcworkspace", "contents.xcworkspacedata")
XCCONFIGS = [
    os.path.join(MACOS, "Flutter", "Flutter-Debug.xcconfig"),
    os.path.join(MACOS, "Flutter", "Flutter-Release.xcconfig"),
]
BACKUP_HOME = os.path.expanduser("~/.openedu-deps")

# xcconfig 里 CocoaPods 的引用行（Flutter 模板写的是 `#include?`，问号=文件缺失也不报错，
# 所以删掉 Pods 目录后其实也能编过——但还是清掉，否则下次 `flutter create` 会困惑）。
POD_INCLUDE_RE = re.compile(r'^\s*#include\??\s+"Pods/Target Support Files/[^"]*"\s*$')

# pbxproj 里 CocoaPods 留下的痕迹：build phase 名 / xcconfig 引用 / Pods 工程引用 / 链接库。
CP_TRACE_RE = re.compile(r"Pods-Runner|\[CP\]|Pods\.xcodeproj|Pods_Runner|libPods|Check Pods Manifest")

# workspace 里指向 Pods 工程的那条 FileRef（整个块一起删）。
# `[^>]` 天然跨行，所以能吃到模板里那种「开标签换行写属性」的写法。
PODS_FILEREF_RE = re.compile(r'[ \t]*<FileRef[^>]*"group:Pods/[^"]*"[^>]*>\s*</FileRef>\n?')


def _rel(path: str) -> str:
    return os.path.relpath(path, FRONTEND)


def _step(label: str, missing: bool, check: bool) -> int:
    """打印一步的结果；missing=True 表示这步还没做。返回 1 表示「检查模式下应判失败」。"""
    if not missing:
        print(f"  [ok]    {label}")
        return 0
    print(f"  [{'would-patch' if check else 'patch'}] {label}")
    return 1 if check else 0


def pod_includes(path: str) -> list[str]:
    """返回该 xcconfig 里所有指向 Pods 的 include 行。"""
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [ln for ln in f.read().splitlines() if POD_INCLUDE_RE.match(ln)]


def cp_traces() -> int:
    if not os.path.exists(PBXPROJ):
        return 0
    with open(PBXPROJ, encoding="utf-8") as f:
        return sum(1 for ln in f if CP_TRACE_RE.search(ln))


# --------------------------------------------------------------------------- 四步


def step_deintegrate(check: bool) -> int:
    """清 pbxproj 里的 CocoaPods 引用。Podfile 没了就说明已清过。"""
    podfile = os.path.join(MACOS, "Podfile")
    traces = cp_traces()
    if not os.path.exists(podfile) and traces == 0:
        return _step("pbxproj: 无 CocoaPods 引用", missing=False, check=check)

    label = f"pbxproj: {traces} 处 CocoaPods 引用待清（在 macos/ 跑 pod deintegrate）"
    if shutil.which("pod") is None:
        print(f"  [error] {label} —— 找不到 pod 命令，这一步无法自动完成")
        return 1
    if check:
        return _step(label, missing=True, check=True)

    # pbxproj 是 Xcode 工程文件，改坏了整个工程打不开 → 动它之前先备份。
    os.makedirs(BACKUP_HOME, exist_ok=True)
    backup = os.path.join(BACKUP_HOME, f"macos-pbxproj-{time.strftime('%Y%m%d-%H%M%S')}.bak")
    shutil.copy2(PBXPROJ, backup)
    print(f"  [patch] {label}（pbxproj 已备份到 {backup}）")

    proc = subprocess.run(["pod", "deintegrate"], cwd=MACOS, capture_output=True, text=True)
    tail = (proc.stdout or "").strip().splitlines()
    for ln in tail[-3:]:
        print(f"          pod: {ln}")
    if proc.returncode != 0:
        print(f"  [error] pod deintegrate 退出码 {proc.returncode}")
        if proc.stderr:
            print(f"          {proc.stderr.strip().splitlines()[-1]}")
        return 1
    return 0


def step_remove_podfile(check: bool) -> int:
    targets = [n for n in ("Podfile", "Podfile.lock") if os.path.exists(os.path.join(MACOS, n))]
    if not targets:
        return _step("macos/: 无 Podfile / Podfile.lock", missing=False, check=check)

    rc = _step(f"macos/: 删除 {', '.join(targets)}", missing=True, check=check)
    if check:
        return rc
    for name in targets:
        os.remove(os.path.join(MACOS, name))
    return rc


def step_remove_pods_dir(check: bool) -> int:
    pods = os.path.join(MACOS, "Pods")
    if not os.path.isdir(pods):
        return _step("macos/: 无 Pods/ 目录", missing=False, check=check)

    rc = _step("macos/: 删除 Pods/（deintegrate 未清干净时的兜底）", missing=True, check=check)
    if check:
        return rc
    shutil.rmtree(pods)
    return rc


def step_clean_xcconfigs(check: bool) -> int:
    changed = 0
    for path in XCCONFIGS:
        if not os.path.exists(path):
            print(f"  [skip]  {_rel(path)} 不存在")
            continue
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
        kept = [ln for ln in lines if not POD_INCLUDE_RE.match(ln)]
        if len(kept) == len(lines):
            print(f"  [ok]    {_rel(path)}: 无 Pods include")
            continue
        print(
            f"  [{'would-patch' if check else 'patch'}] {_rel(path)}: 移除 {len(lines) - len(kept)} 行 Pods include"
        )
        if check:
            changed += 1
            continue
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(kept))
            if kept:
                f.write("\n")
    return 1 if (check and changed) else 0


def step_clean_workspace(check: bool) -> int:
    """`pod deintegrate` 留下的那条「workspace 仍引用 Pods 工程」——它自己不清。"""
    if not os.path.exists(WORKSPACE_DATA):
        print(f"  [skip]  {_rel(WORKSPACE_DATA)} 不存在")
        return 0
    with open(WORKSPACE_DATA, encoding="utf-8") as f:
        original = f.read()
    cleaned = PODS_FILEREF_RE.sub("", original)
    if cleaned == original:
        print(f"  [ok]    {_rel(WORKSPACE_DATA)}: 未引用 Pods 工程")
        return 0
    rc = _step(f"{_rel(WORKSPACE_DATA)}: 移除对已删除 Pods/Pods.xcodeproj 的引用", missing=True, check=check)
    if check:
        return rc
    os.makedirs(BACKUP_HOME, exist_ok=True)
    shutil.copy2(
        WORKSPACE_DATA,
        os.path.join(BACKUP_HOME, f"macos-xcworkspacedata-{time.strftime('%Y%m%d-%H%M%S')}.bak"),
    )
    with open(WORKSPACE_DATA, "w", encoding="utf-8") as f:
        f.write(cleaned)
    return rc


# --------------------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="只检查不写入；未迁移完成则退出码 1")
    args = parser.parse_args()
    check = args.check

    if not os.path.isdir(MACOS):
        print(f"[error] 找不到 {MACOS}（平台目录未生成？先跑 flutter create 或 pub get）")
        return 1

    verb = "检查" if check else "迁移"
    print(f"macOS CocoaPods → SwiftPM {verb}（{_rel(MACOS)}）\n")

    print("CocoaPods 集成:")
    changed = 0
    changed += step_deintegrate(check)
    changed += step_remove_podfile(check)
    changed += step_remove_pods_dir(check)
    changed += step_clean_xcconfigs(check)
    changed += step_clean_workspace(check)

    print()
    if check:
        if changed:
            print(f"[fail] 仍有 {changed} 项待迁移 —— 跑一次不带 --check 的脚本")
            return 1
        print("[ok] 已是纯 SwiftPM 工程")
        return 0

    print("[done] 迁移完成。仍需完整重跑 App：")
    print("       cd frontend && flutter clean && flutter run -d macos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
