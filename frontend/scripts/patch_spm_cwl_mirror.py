#!/usr/bin/env python3
"""把 `CwlCatchException` 的 SwiftPM 依赖解析到本机镜像，绕开直连 GitHub（ADR-0063 §10）。

背景（坑，两个叠加才踩到）：

1. `speech_to_text` 的 `darwin/speech_to_text/Package.swift` 里硬编码了一条远程依赖
   `.package(url: "https://github.com/mattgallagher/CwlCatchException.git", from: "2.0.0")`。
   它不在 pubspec 里、也不在我们的仓库里 —— 换不掉，只能让它解析成功。

2. SwiftPM 拉 git 依赖走的是 **libgit2**，它**只认 SwiftPM 自己的 mirror 配置**，不认
   gitconfig 的 `url.<x>.insteadOf`（那是 git 命令行的特性）。所以「配了 insteadOf 仍然
   报同样的错」是必然结果：SwiftPM 压根没看那行配置，还是直连 GitHub 要 tag 列表。

3. 还有一根暗桩：全局 gitconfig 里若有 `safe.bareRepository = explicit`，libgit2 会拒绝
   打开 SwiftPM 的缓存仓库（那些都是 bare 仓库），报
   `fatal: cannot use bare repository '...' (safe.bareRepository is 'explicit')`。
   表现同样是「Couldn't get the list of tags」，但根因已经在本地了。git 的默认值是 `all`，
   本脚本把它恢复成默认（原值会打印出来并备份，便于还原）。

于是正确解法是 SwiftPM 的 mirror：把远程 URL 映射到本机一个 bare 仓库（`file://`），
libgit2 从本地拿 refs，全程离线。

改的位置有三处（都是**不在版本控制里**的东西，所以必须脚本化、幂等、可重跑）：

  ~/.swiftpm/configuration/mirrors.json                                       机器级，兜底
  macos/Runner.xcworkspace/xcshareddata/swiftpm/configuration/mirrors.json    工程级
  macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/.../mirrors.json    工程级

镜像仓库本体在 `~/.openedu-deps/CwlCatchException.git`：优先从 SwiftPM 自己的缓存
`~/Library/Caches/org.swift.swiftpm/repositories/CwlCatchException-*` 复制（离线），
缓存没有才 `git clone --mirror`（走 git 命令行，会读 gitconfig 的代理，能通）。

用法：
    python3 frontend/scripts/patch_spm_cwl_mirror.py          # 补齐（幂等，可反复跑）
    python3 frontend/scripts/patch_spm_cwl_mirror.py --check  # 只检查不写入；缺则退出码 1

`--check` 的用法同 `patch_voice_permissions.py`：把「构建时才炸」变成构建前一条会失败的
检查。⚠️ 本脚本只解决依赖**解析**；补齐后仍需完整重跑 App（新插件的原生注册不随热重载生效）。
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FRONTEND = os.path.normpath(os.path.join(HERE, ".."))

# 远程依赖的原始 URL：必须与 speech_to_text 的 Package.swift 里的完全一致（含 .git）。
ORIGINAL_URL = "https://github.com/mattgallagher/CwlCatchException.git"
# 该依赖的最低版本约束是 from: 2.0.0，解析时会取该 major 下的最新 tag。
REQUIRED_TAG = "2.2.1"

DEPS_HOME = os.path.expanduser("~/.openedu-deps")
MIRROR_DIR = os.path.join(DEPS_HOME, "CwlCatchException.git")
MIRROR_URL = f"file://{MIRROR_DIR}"

SPM_CACHE_HOME = os.path.expanduser("~/Library/Caches/org.swift.swiftpm/repositories")
GLOBAL_MIRRORS = os.path.expanduser("~/.swiftpm/configuration/mirrors.json")
GITCONFIG_BACKUP = os.path.join(DEPS_HOME, "gitconfig-safe-bareRepository.backup")

# 工程级：xcodebuild 按 workspace 找这个路径；两个 workspace 都写，省得猜用哪个。
PROJECT_MIRRORS = [
    os.path.join(FRONTEND, "macos", "Runner.xcworkspace", "xcshareddata", "swiftpm", "configuration", "mirrors.json"),
    os.path.join(
        FRONTEND, "macos", "Runner.xcodeproj", "project.xcworkspace", "xcshareddata", "swiftpm", "configuration", "mirrors.json"
    ),
]


def _run(args: list[str]) -> tuple[int, str]:
    try:
        proc = subprocess.run(args, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return 127, ""
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def mirror_has_tag() -> bool:
    """镜像仓库里有没有我们要的 tag。

    不用 `git -C ... tag`：全局 gitconfig 的 `safe.bareRepository=explicit` 会让 git 拒绝
    操作裸库（报错，不是返回空）。`git ls-remote` 不受这条限制。
    """
    if not os.path.isdir(os.path.join(MIRROR_DIR, "objects")):
        return False
    code, out = _run(["git", "ls-remote", "--tags", MIRROR_URL])
    return code == 0 and f"refs/tags/{REQUIRED_TAG}" in out


def ensure_mirror(check: bool) -> int:
    """保证本地镜像仓库存在且带 REQUIRED_TAG。返回缺失/待补的数量（0 = 已就位）。"""
    label = os.path.relpath(MIRROR_DIR, os.path.expanduser("~"))
    if mirror_has_tag():
        print(f"  [ok]    ~/{label}: 镜像仓库已就位，含 tag {REQUIRED_TAG}")
        return 0

    # 优先 SwiftPM 自己的缓存：它是同一个仓库的 bare clone，离线可得。
    cache = None
    if os.path.isdir(SPM_CACHE_HOME):
        for name in sorted(os.listdir(SPM_CACHE_HOME)):
            if name.startswith("CwlCatchException-") and os.path.isdir(os.path.join(SPM_CACHE_HOME, name)):
                cache = os.path.join(SPM_CACHE_HOME, name)
                break

    action = "从 SwiftPM 缓存复制" if cache else f"从 {ORIGINAL_URL} clone --mirror"
    print(f"  [{'would-patch' if check else 'patch'}] ~/{label}: 缺镜像/缺 tag {REQUIRED_TAG}（{action}）")
    if check:
        return 1

    os.makedirs(DEPS_HOME, exist_ok=True)
    if os.path.exists(MIRROR_DIR):
        shutil.rmtree(MIRROR_DIR)
    if cache:
        shutil.copytree(cache, MIRROR_DIR)
    else:
        code, out = _run(["git", "clone", "--mirror", ORIGINAL_URL, MIRROR_DIR])
        if code != 0:
            print(f"  [error] git clone --mirror 失败（退出码 {code}）：{out.strip()}", file=sys.stderr)
            print("         git 命令行会读 gitconfig 的代理；若 GitHub 直连不通，先配 http 代理再跑。", file=sys.stderr)
            return 1

    if not mirror_has_tag():
        print(f"  [error] ~/{label}: 建好了但仍缺 tag {REQUIRED_TAG}", file=sys.stderr)
        return 1
    print(f"  [done]  ~/{label}: 已建好，含 tag {REQUIRED_TAG}")
    return 0


def _load_mirrors(path: str) -> dict:
    """读入一份 mirrors.json，把历史格式统一成当前 schema。

    ⚠️ 踩过的坑：SwiftPM 6.x 的 schema 是 `{"version": 1, "object": [ ...条目直接是数组... ]}`。
    按网上老资料写成 `{"object": {"mirrors": [...]}}` 会直接崩：
    `DecodingError.typeMismatch: expected Array<Any> ... Path: object`。
    格式以 `swift package config set-mirror` 的输出为准，不要凭记忆写。
    """
    empty = {"version": 1, "object": []}
    if not os.path.exists(path):
        return empty
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return empty
    if not isinstance(data, dict):
        return empty

    obj = data.get("object")
    if isinstance(obj, list):  # 当前 schema
        return {"version": data.get("version", 1), "object": list(obj)}
    if isinstance(obj, dict) and isinstance(obj.get("mirrors"), list):  # 老 schema
        return {"version": data.get("version", 1), "object": list(obj["mirrors"])}
    if isinstance(data.get("mirrors"), list):  # 顶层数组的老老 schema
        return {"version": data.get("version", 1), "object": list(data["mirrors"])}
    return empty


def _entry() -> dict:
    # 与 `swift package config set-mirror` 生成的字段保持一致（只有 mirror/original）。
    return {"mirror": MIRROR_URL, "original": ORIGINAL_URL}


def _label(path: str) -> str:
    home = os.path.expanduser("~")
    if path.startswith(home):
        return "~" + path[len(home):]
    rel = os.path.relpath(path, FRONTEND)
    return rel if not rel.startswith("..") else path


def patch_mirrors_file(path: str, check: bool) -> int:
    """往一份 mirrors.json 里补/改本条映射，其他条目原样保留。"""
    label = _label(path)
    data = _load_mirrors(path)
    mirrors = data["object"]

    existing = next((m for m in mirrors if isinstance(m, dict) and m.get("original") == ORIGINAL_URL), None)
    if existing is not None and existing.get("mirror") == MIRROR_URL:
        print(f"  [ok]    {label}: 映射已就位")
        return 0

    verb = "改" if existing is not None else "补"
    print(f"  [{'would-patch' if check else 'patch'}] {label}: {verb}映射 {ORIGINAL_URL} -> {MIRROR_URL}")
    if check:
        return 1

    if existing is not None:
        existing.update(_entry())
    else:
        mirrors.append(_entry())
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    return 0


def ensure_gitconfig(check: bool) -> int:
    """清掉 `safe.bareRepository = explicit`：它会让 libgit2 拒绝打开 SwiftPM 的裸缓存仓库。

    不直接改 ini 文本，走 `git config` 命令；改之前把原值写进备份文件，方便还原。
    """
    code, out = _run(["git", "config", "--global", "--get-all", "safe.bareRepository"])
    values = [v.strip() for v in out.splitlines() if v.strip()]
    blocking = [v for v in values if v == "explicit"]

    if not blocking:
        print(f"  [ok]    gitconfig: safe.bareRepository 不含 explicit（当前: {values or ['未设置=默认 all']}）")
        return 0

    print("  [{}] gitconfig: 移除 safe.bareRepository=explicit（libgit2 会据此拒绝打开 SwiftPM 的 bare 缓存仓库）".format(
        "would-patch" if check else "patch"))
    if check:
        return 1

    os.makedirs(DEPS_HOME, exist_ok=True)
    with open(GITCONFIG_BACKUP, "w", encoding="utf-8") as f:
        f.write("\n".join(values) + "\n")
    print(f"  [note]  原值已备份到 {_label(GITCONFIG_BACKUP)}；还原：git config --global --add safe.bareRepository explicit")

    _run(["git", "config", "--global", "--unset-all", "safe.bareRepository"])
    for v in values:
        if v != "explicit":  # 保留同一键上的其他（非阻塞）取值
            _run(["git", "config", "--global", "--add", "safe.bareRepository", v])
    print("  [done]  gitconfig: 已恢复为 git 默认值（all）")
    return 0


def refresh_spm_cache(check: bool) -> int:
    """把 SwiftPM 对 CwlCatchException 的旧缓存挪走。

    旧缓存的 origin 指向 GitHub。一旦 mirror 生效，SwiftPM 若命中这份缓存，可能仍然照
    origin 去 fetch（又回到直连失败）。挪走后它会按镜像 URL 重新 clone，本地几秒完成。
    用 move 到备份目录而不是删除：可随时手动还原。
    """
    if not os.path.isdir(SPM_CACHE_HOME):
        print("  [skip]  SwiftPM 缓存目录不存在")
        return 0

    stale, fresh = [], []
    for name in sorted(os.listdir(SPM_CACHE_HOME)):
        path = os.path.join(SPM_CACHE_HOME, name)
        if not name.startswith("CwlCatchException-") or not os.path.isdir(path):
            continue
        # 只看缓存仓库自己的 origin：mirror 生效后新建的缓存指向 file:// 镜像，留着能加速，
        # 不能一律挪走 —— 否则每次解析重建一份、每次跑脚本又挪走一份，白折腾。
        _, url = _run(["git", "config", "--file", os.path.join(path, "config"), "--get", "remote.origin.url"])
        (stale if url.strip().startswith("http") else fresh).append(path)

    if fresh:
        print(f"  [ok]    SwiftPM 缓存: {len(fresh)} 份已指向本地镜像，保留")
    if not stale:
        return 0

    backup = os.path.join(DEPS_HOME, f"spm-cache-backup-{time.strftime('%Y%m%d-%H%M%S')}")
    print(f"  [{'note' if check else 'patch'}] SwiftPM 缓存: {len(stale)} 份仍指向 GitHub，待挪到 {_label(backup)}")
    if check:
        return 0  # 旧缓存可被重新 clone 覆盖，不算「缺配置」，不拦 --check

    os.makedirs(backup, exist_ok=True)
    for src in stale:
        shutil.move(src, os.path.join(backup, os.path.basename(src)))
        print(f"  [done]  已挪走 {os.path.basename(src)}")
    return 0


def main(argv: list[str]) -> int:
    check = "--check" in argv[1:]
    verb = "检查" if check else "补齐"

    print(f"{verb} CwlCatchException 的 SwiftPM 镜像映射（ADR-0063 §10）\n")
    print("镜像仓库:")
    changed = ensure_mirror(check)
    print("\nmirrors.json:")
    for path in [GLOBAL_MIRRORS] + PROJECT_MIRRORS:
        changed += patch_mirrors_file(path, check)
    print("\ngitconfig:")
    changed += ensure_gitconfig(check)
    print("\nSwiftPM 缓存:")
    refresh_spm_cache(check)

    if check:
        if changed:
            print(f"\n[fail] 缺 {changed} 项配置。运行不带 --check 的同一脚本补齐：")
            print("       python3 frontend/scripts/patch_spm_cwl_mirror.py")
            return 1
        print("\n[ok] 镜像映射齐全。")
        return 0

    print("\n[done] 已应用补丁。重新构建即可生效：")
    print("       cd frontend && flutter clean && flutter run -d macos")
    print("       ⚠️ 新增原生插件须完整重跑 App，Hot Restart 不补原生注册。")
    print("       （解析失败只发生在「新增/变更 SwiftPM 依赖」时；本脚本不解决代码编译问题。）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
