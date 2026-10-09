#!/usr/bin/env bash
# 录制 openedu（macOS 桌面端）窗口 —— 按窗口精确录制，不录到桌面杂乱。
#
# 用法：
#   ./submission_docs/record_app.sh 1                    # 录第 1 段 → submission_docs/raw/demo_01.mov（Ctrl-C 停止）
#   DURATION=90 ./submission_docs/record_app.sh 2        # 录 90 秒后自动停
#   APPNAME=kids_learn ./submission_docs/record_app.sh 3 # 显式指定进程名
#   REGION=100,200,1280,800 ./submission_docs/record_app.sh 4   # 手动指定区域，跳过探测
#
# 开关：
#   CLICK=0    不显示鼠标点击（默认显示）
#   CURSOR=0   不录光标（默认录）
#   OUT=/path  自定义输出文件（默认 submission_docs/raw/demo_<段号>.mov，与 cwd 无关）
#
# 首次运行需授权：系统设置 → 隐私与安全性 → 屏幕录制，勾选你跑脚本的终端。
#
# 实现说明（为什么不用 lsappinfo + -R）：
#   - macOS 26 起 `lsappinfo … -only WindowBounds` 恒返回 [ NULL ]，取坐标这条路已废。
#   - `screencapture -v -i` 会直接报 "video not valid with -i"：视频模式不再接受 -i。
#   - 改用 CoreGraphics 窗口列表拿到 windowid，再 `-v -l <id>` 按窗口录：
#     窗口被遮挡 / 移到哪都跟随，且不录阴影与桌面。swift 随 Xcode CLT 自带（Flutter 开发必备），
#     零第三方依赖；swift 不可用时退到 System Events 取坐标 + `-R` 区域录。
#
# 注意：本脚本须兼容 macOS 自带的 bash 3.2 —— 变量引用一律写成 ${VAR}，
#       不要 `$VAR` 直接贴中文字符（bash 3.2 会把多字节首字节并进变量名 → unbound variable）。
# 若被 zsh / sh 直接调用，重新用 bash 执行（本脚本依赖 bash 的未加引号展开语义）
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: record_app.sh <段号 1-7>"
  echo "      [DURATION=秒数] [APPNAME=进程名] [REGION=x,y,w,h]"
  exit 1
fi
case "$1" in
  ''|*[!0-9]*) echo "段号必须是数字（1-7），收到：$1"; exit 1 ;;
esac
# 补零成两位：gen_subs.py 按 demo_01.mov … demo_07.mov 查找
SEG="$(printf '%02d' "$1")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# 输出固定在 submission_docs/raw/（gen_subs.py 的输入目录），与调用时的 cwd 无关
RAW_DIR="${SCRIPT_DIR}/raw"
DEFAULT_OUT="${RAW_DIR}/demo_${SEG}.mov"
OUT="${OUT:-${DEFAULT_OUT}}"
mkdir -p "$(dirname "${OUT}")"

DUR_ARG=""
STOP_HINT="Ctrl-C 停止"
if [[ -n "${DURATION:-}" ]]; then
  DUR_ARG="-V ${DURATION}"
  STOP_HINT="Ctrl-C 停止，${DURATION}s 后自动停"
fi

# 视频通用标志：-v 视频 / -o 不录阴影 / -x 静音 / -C 录光标 / -k 显示点击
FLAGS="-o -x"
if [[ "${CURSOR:-1}" != "0" ]]; then FLAGS="${FLAGS} -C"; fi
if [[ "${CLICK:-1}"  != "0" ]]; then FLAGS="${FLAGS} -k"; fi

# ── 1) 探测应用进程名：取 bundle 落在本仓库内的前台 App（产物名随项目而变，不硬编码）
detect_app() {
  lsappinfo list 2>/dev/null | awk -v ROOT="${REPO_ROOT}" '
    /^[[:space:]]*[0-9]+\) "/ { n=$0; sub(/^[[:space:]]*[0-9]+\) "/,"",n); sub(/".*/,"",n); name=n }
    /bundle path=/ { p=$0; sub(/.*bundle path="/,"",p); sub(/".*/,"",p);
                     if (index(p, ROOT) > 0) print name }
  ' | head -1
}

# ── 2) 取窗口 id：CoreGraphics 窗口列表，挑该 App 最大的 layer=0 窗口
window_id() {
  command -v swift >/dev/null 2>&1 || return 0
  APP="$1" swift -e '
import CoreGraphics
import Foundation
let app = ProcessInfo.processInfo.environment["APP"] ?? ""
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
var best = 0
var area = 0.0
for w in list {
    guard (w[kCGWindowLayer as String] as? Int ?? -1) == 0 else { continue }
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    guard app.isEmpty || owner == app else { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let a = (b["Width"] as? Double ?? 0) * (b["Height"] as? Double ?? 0)
    if a > area { area = a; best = w[kCGWindowNumber as String] as? Int ?? 0 }
}
print(best)
' 2>/dev/null | tail -1
}

# ── 3) 二级兜底：System Events 取窗口坐标（需给终端「辅助功能」权限）
window_region() {
  command -v osascript >/dev/null 2>&1 || return 0
  osascript -e "tell application \"System Events\" to tell process \"$1\" to get {position, size} of window 1" 2>/dev/null \
    | tr -d ' \n'
}

record_window() {  # $1 = windowid
  echo "▶ 按窗口录制：App「${APP}」windowid=$1"
  echo "  录制中…（${STOP_HINT}）"
  # shellcheck disable=SC2086
  screencapture -v -l "$1" ${FLAGS} ${DUR_ARG} "${OUT}" || true
}

record_region() {  # $1 = x,y,w,h
  echo "▶ 按区域录制：$1"
  echo "  录制中…（${STOP_HINT}；期间请勿移动窗口）"
  # shellcheck disable=SC2086
  screencapture -v -R "$1" ${FLAGS} ${DUR_ARG} "${OUT}" || true
}

# ── 主流程 ─────────────────────────────────────────────────────────────
if [[ -n "${REGION:-}" ]]; then
  record_region "${REGION}"
  echo "✅ 完成：${OUT}"
  exit 0
fi

APP="${APPNAME:-$(detect_app)}"
APP_LABEL="${APP}"
if [[ -z "${APP_LABEL}" ]]; then APP_LABEL="(未识别)"; fi

if [[ -n "${APP}" ]]; then
  echo "▶ 定位「${APP}」窗口…"
  WID="$(window_id "${APP}")"
  if [[ -n "${WID}" && "${WID}" != "0" ]]; then
    record_window "${WID}"
    echo "✅ 完成：${OUT}"
    exit 0
  fi

  REG="$(window_region "${APP}")"
  if [[ "${REG}" =~ ^-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+$ ]]; then
    record_region "${REG}"
    echo "✅ 完成：${OUT}"
    exit 0
  fi
fi

echo "⚠ 未找到可录制的窗口（App「${APP_LABEL}」）。"
echo "   排查：① 确认已 flutter run -d macos 且窗口未最小化；"
echo "         ② 已给终端「屏幕录制」权限（缺权限会录出黑屏）。"
echo "   也可显式指定：APPNAME=<进程名> ./record_app.sh ${SEG}"
echo "                REGION=x,y,w,h ./record_app.sh ${SEG}"
echo "  → 回退交互模式：拖拽框选 openedu 窗口区域。"
# 交互式视频录制：视频模式不接受 -i，用 -J video 进入框选
# shellcheck disable=SC2086
screencapture -v -J video -x ${DUR_ARG} "${OUT}" || true
echo "✅ 完成：${OUT}"
