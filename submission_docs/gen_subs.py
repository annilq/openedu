"""生成演示视频 7 段字幕 (SRT) 并烧入视频 (ffmpeg hard-burn)。

设计前提：用户先手动录屏（仅视频、不录声音），本脚本在最后一步把字幕
以"硬烧入"方式嵌入，产出自包含 mp4（任意播放器都看得到字幕，无需字幕轨）。

与 gen_voice.py 共用同一份 7 段旁白文本（从 narration.md 加载，单一事实源）。

用法（在 submission_docs/ 目录下运行）：
  # 仅生成 SRT（录制后运行；缺片时用 --default-dur 给占位时长预览）
  python gen_subs.py

  # 生成 SRT 并硬烧入每一段 -> out/out_01.mp4 ... out/out_07.mp4
  python gen_subs.py --burn

  # 烧入后再合并为 final_demo.mp4（≤8 分钟由你前期分段时长控制）
  python gen_subs.py --burn --concat

依赖：ffmpeg / ffprobe（已确认 /opt/homebrew/bin 下可用）。
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# 复用配音脚本里的同一份旁白（从 narration.md 加载），避免两处文本漂移
from gen_voice import load_segments, NARRATION
SEGMENTS = load_segments(NARRATION)

HERE = Path(__file__).resolve().parent
RAW = HERE / "raw"          # 录制产物放这里：demo_01.mp4 ... demo_07.mp4
SUBS = HERE / "subs"        # 生成的 SRT
OUT = HERE / "out"          # 烧入后的片段
SUBS.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

FFMPEG = "/opt/homebrew/bin/ffmpeg"
FFPROBE = "/opt/homebrew/bin/ffprobe"

# 字幕样式：白字 + 半透明黑底 + 苹方（macOS 自带中文 CJK 字体，避免豆腐块）
SUB_STYLE = (
    "FontSize=30,PrimaryColour=&HFFFFFF&,BackColour=&H80000000&,"
    "Bold=1,Alignment=2,FontName=PingFang SC"
)


def seg_num(key: str) -> str:
    return key[3:]  # "seg01" -> "01"


def find_clip(num: str) -> Path | None:
    for ext in ("mp4", "mov", "mkv"):
        p = RAW / f"demo_{num}.{ext}"
        if p.exists():
            return p
    return None


def clip_duration(path: Path) -> float:
    out = subprocess.run(
        [FFPROBE, "-v", "error", "-show_entries", "format=duration",
         "-of", "json", str(path)],
        capture_output=True, text=True,
    )
    try:
        return float(json.loads(out.stdout)["format"]["duration"])
    except Exception:
        return 0.0


def split_sentences(text: str) -> list[str]:
    # 按中文/英文句末标点切分，保留可读短句
    parts = re.split(r"[。！？!?；;]", text)
    return [p.strip() for p in parts if p.strip()]


def srt_time(sec: float) -> str:
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = int(sec % 60)
    ms = int((sec - int(sec)) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def build_srt(key: str, text: str, duration: float) -> Path:
    sents = split_sentences(text)
    n = max(len(sents), 1)
    slice_t = duration / n
    lines = []
    for i, sent in enumerate(sents):
        start = i * slice_t
        end = (i + 1) * slice_t - 0.2  # 段间留 0.2s 间隙
        lines.append(f"{i + 1}")
        lines.append(f"{srt_time(start)} --> {srt_time(max(end, start + 1))}")
        lines.append(sent)
        lines.append("")
    srt = SUBS / f"{key}.srt"
    srt.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return srt


def burn(clip: Path, srt: Path, num: str) -> Path:
    dst = OUT / f"out_{num}.mp4"
    vf = f"subtitles={srt.name}:force_style='{SUB_STYLE}'"
    subprocess.run(
        [FFMPEG, "-y", "-i", str(clip),
         "-vf", vf,
         "-c:v", "libx264", "-c:a", "aac", "-movflags", "+faststart",
         str(dst)],
        check=True,
    )
    return dst


def concat() -> Path:
    files = []
    for key in SEGMENTS:
        num = seg_num(key)
        p = OUT / f"out_{num}.mp4"
        if p.exists():
            files.append(p)
    if not files:
        print("[gen_subs] 没有可合并的 out_*.mp4，先跑 --burn")
        return Path()
    lst = HERE / "filelist.txt"
    lst.write_text("\n".join(f"file '{f}'" for f in files), encoding="utf-8")
    dst = HERE / "final_demo.mp4"
    subprocess.run(
        [FFMPEG, "-y", "-f", "concat", "-safe", "0", "-i", str(lst),
         "-c", "copy", str(dst)],
        check=True,
    )
    return dst


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--burn", action="store_true", help="生成 SRT 后硬烧入每段视频")
    ap.add_argument("--concat", action="store_true", help="烧入后合并为 final_demo.mp4")
    ap.add_argument("--default-dur", type=float, default=60.0,
                    help="录制片缺失时使用的占位时长（秒），用于预览 SRT")
    args = ap.parse_args()

    if args.concat and not args.burn:
        args.burn = True  # concat 依赖烧入产物

    for key, text in SEGMENTS.items():
        num = seg_num(key)
        clip = find_clip(num)
        if clip:
            dur = clip_duration(clip)
            print(f"[gen_subs] {key}: 读片 {clip.name} 时长 {dur:.1f}s")
        else:
            dur = args.default_dur
            print(f"[gen_subs] {key}: 未找到 demo_{num}.*，用占位 {dur:.0f}s 预览")
        srt = build_srt(key, text, dur)
        print(f"[gen_subs]   写 SRT -> {srt.name}")

        if args.burn:
            if clip:
                dst = burn(clip, srt, num)
                print(f"[gen_subs]   烧入 -> {dst.name}")
            else:
                print(f"[gen_subs]   ⚠️ 跳过烧入（无 demo_{num} 片段）")

    if args.concat:
        final = concat()
        if final:
            print(f"[gen_subs] 合并完成 -> {final.name}")


if __name__ == "__main__":
    main()
