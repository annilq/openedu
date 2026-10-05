#!/usr/bin/env python3
"""幂等地补齐「语音输入」所需的平台权限声明（ADR-0063 §10）。

背景（坑）：`frontend/.gitignore` 第 20–25 行忽略 `android / linux / macos / web /
windows / ios`，即**平台目录全是本机生成物、不在版本控制里**。而语音输入依赖三处
只有平台文件才能声明的东西：

  iOS     Info.plist  `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription`
  macOS   Info.plist  同上两项
          *.entitlements `com.apple.security.device.audio-input`（App Sandbox 已开启，
                         缺这一项麦克风在系统层直接被拒，且**不报错**）
  Android AndroidManifest.xml `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`

缺任一处的失效方式都是**静默**的：`SpeechToText.initialize()` 返回 false → 能力门禁
（ADR-0063 §2）判定为 `unsupported` → 麦按钮根本不渲染 → 界面上看不出任何异常，
用户只会以为「这个版本没有语音」。所以 `flutter create` 重新生成平台目录、或换机器
构建之后，必须跑一次本脚本。

用法：
    python3 frontend/scripts/patch_voice_permissions.py          # 补齐（幂等，可反复跑）
    python3 frontend/scripts/patch_voice_permissions.py --check  # 只检查不写入；缺则退出码 1

`--check` 是给 CI / 构建前自检用的：它把上面那种静默失效变成一条会失败的检查。
"""
from __future__ import annotations

import os
import plistlib
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FRONTEND = os.path.normpath(os.path.join(HERE, ".."))

# iOS / macOS 共用：请求麦克风与语音识别授权时系统弹窗展示的文案。
# 必须写清「用来干什么」——只写「需要麦克风权限」会被 App Store 审核拒。
INFO_PLIST_PATCHES = {
    "NSMicrophoneUsageDescription": "用于语音输入，把你说的话转成文字，方便直接提问。",
    "NSSpeechRecognitionUsageDescription": "用于语音输入，把你说的话转成文字发给 AI 学习助手。",
}

# macOS：App Sandbox 下访问麦克风必须显式申请，否则系统直接拒绝且不报错。
MACOS_ENTITLEMENT_PATCHES = {
    "com.apple.security.device.audio-input": True,
}
MACOS_ENTITLEMENTS = ["DebugProfile.entitlements", "Release.entitlements"]

ANDROID_MANIFEST = os.path.join("android", "app", "src", "main", "AndroidManifest.xml")
ANDROID_PERMISSION = "android.permission.RECORD_AUDIO"
ANDROID_PERMISSION_LINE = f'    <uses-permission android:name="{ANDROID_PERMISSION}"/>'


def _patch_plist(path: str, patches: dict[str, object], check: bool) -> int:
    """往 plist 写键值：缺才补，值不同才改。返回发生的改动数。"""
    label = os.path.relpath(path, FRONTEND)
    if not os.path.exists(path):
        print(f"  [skip]  {label}: 目录不存在（该平台未生成）")
        return 0

    with open(path, "rb") as f:
        plist = plistlib.load(f)

    missing = {k: v for k, v in patches.items() if plist.get(k) != v}
    if not missing:
        print(f"  [ok]    {label}: {len(patches)} 项权限已就位")
        return 0

    for k, v in missing.items():
        print(f"  [{'would-patch' if check else 'patch'}] {label}: {k}")

    if not check:
        plist.update(missing)
        with open(path, "wb") as f:
            plistlib.dump(plist, f)
    return len(missing)


def patch_ios(check: bool) -> int:
    print("iOS:")
    return _patch_plist(
        os.path.join(FRONTEND, "ios", "Runner", "Info.plist"),
        INFO_PLIST_PATCHES,
        check,
    )


def patch_macos(check: bool) -> int:
    print("macOS:")
    changed = _patch_plist(
        os.path.join(FRONTEND, "macos", "Runner", "Info.plist"),
        INFO_PLIST_PATCHES,
        check,
    )
    for name in MACOS_ENTITLEMENTS:
        changed += _patch_plist(
            os.path.join(FRONTEND, "macos", "Runner", name),
            MACOS_ENTITLEMENT_PATCHES,
            check,
        )
    return changed


def patch_android(check: bool) -> int:
    print("Android:")
    path = os.path.join(FRONTEND, ANDROID_MANIFEST)
    label = ANDROID_MANIFEST
    if not os.path.exists(path):
        print(f"  [skip]  {label}: 目录不存在（该平台未生成）")
        return 0

    with open(path, encoding="utf-8") as f:
        text = f.read()

    if ANDROID_PERMISSION in text:
        print(f"  [ok]    {label}: {ANDROID_PERMISSION} 已声明")
        return 0

    print(f"  [{'would-patch' if check else 'patch'}] {label}: {ANDROID_PERMISSION}")
    if check:
        return 1

    # 插到 <manifest ...> 开标签之后：uses-permission 必须是 manifest 的直接子元素，
    # 放进 <application> 里不会生效。
    opening = re.search(r"^[ \t]*<manifest[^>]*>[ \t]*$", text, re.MULTILINE)
    if opening is None:
        print(f"  [error] {label}: 找不到 <manifest> 开标签，未改动", file=sys.stderr)
        return 0
    at = opening.end()
    text = f"{text[:at]}\n{ANDROID_PERMISSION_LINE}{text[at:]}"
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return 1


def main(argv: list[str]) -> int:
    check = "--check" in argv[1:]
    verb = "检查" if check else "补齐"

    print(f"{verb}语音输入平台权限（ADR-0063 §10）: {FRONTEND}\n")
    changed = patch_ios(check) + patch_macos(check) + patch_android(check)

    if check:
        if changed:
            print(f"\n[fail] 缺 {changed} 项权限声明。运行不带 --check 的同一脚本补齐：")
            print("       python3 frontend/scripts/patch_voice_permissions.py")
            return 1
        print("\n[ok] 权限声明齐全。")
        return 0

    if changed:
        print("\n[done] 已应用补丁。重新构建即可生效（原生权限不随热重载生效）：")
        print("       flutter build macos --debug    # 或 flutter run -d macos")
        print("       ⚠️ 新增原生插件须完整重跑 App，Hot Restart 不补原生注册。")
    else:
        print("\n[done] 无需改动，权限声明已齐全。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
