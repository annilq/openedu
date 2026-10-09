"""演示成片合成：按**实际录屏时长**适配配音与字幕 → 烧字幕 → 合并。

为什么不再用「计划时长」：录制时人的手速和 AI 等待时长每次都不一样，
实测 14 段合计 6:00，而旁白只有 4:18，个别段视频是旁白的 3.8 倍。
所以时间轴一律取**事实源**，不再依赖 narration.md 标题里的估算时间。

三段式流程
  1) 字幕  —— 时间轴 = 配音实际时长（ffprobe 量出的 mp3 长度），按句子字数
              占比切片，整段字幕落在语音区间内 → subs/segNN.srt
  2) 贴合  —— 录屏变速，使其长度 ≈ 配音长度（配音本身不变速，全片语速一致）
              · 视频偏长 → 加速，上限 --max-speed（默认 5.0 倍）
              · 视频偏短 → 减速，下限 --min-speed（默认 0.85 倍），
                仍差的部分**定格最后一帧**补齐，保证旁白不被截断
  3) 合成  —— 字幕硬烧进画面 + 配音铺上音轨 → out/out_NN.mp4，
              再按序无损拼接 → final_demo.mp4

用法（在 submission_docs/ 目录下运行）
  # 只出字幕（预览用，不渲染视频，秒出）
  python gen_subs.py

  # 全流程：出字幕 + 变速贴合 + 烧入 + 合并
  python gen_subs.py --all

  # 只渲染一段试看（改参数后先验证再全量）
  python gen_subs.py --all --only 1

  # 微调：更激进的加速上限 / 不减速 / 关掉变速
  python gen_subs.py --all --max-speed 4.0
  python gen_subs.py --all --min-speed 1.0
  python gen_subs.py --all --no-fit          # 视频完全不动，配音铺上去

产物
  subs/segNN.srt   分段字幕（输出时间轴，即变速后的时间轴）
  subs/all.srt     整片字幕（累计偏移，可直接拖进剪辑软件）
  out/out_NN.mp4   分段成片
  final_demo.mp4   最终成片

依赖：ffmpeg / ffprobe（/opt/homebrew/bin）、PingFang SC（macOS 自带）。
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
RAW = HERE / "raw"          # 录制产物：demo_01.mov ... demo_14.mov
VOICE = HERE / "voice"      # 配音产物：seg01.mp3 ...（字幕时间轴事实源）
SUBS = HERE / "subs"        # 生成的 SRT
OUT = HERE / "out"          # 烧入后的分段成片
SUBS.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)

FFMPEG = "/opt/homebrew/bin/ffmpeg"
FFPROBE = "/opt/homebrew/bin/ffprobe"

# 字幕样式：白字 + 黑描边 + 苹方（macOS 自带中文 CJK 字体，避免豆腐块）。
# ⚠️ FontSize 不是像素：libass 对无 PlayRes 的字幕按 288 高度基准缩放，
#    实际字号 = FontSize × 画面高 / 288（本片 1006 高 → 约 3.49 倍）。
#    13 在这个 954×1006 的窗口上约合 45px，长句自动折成 2 行。
# 描边而非色块：画面是浅色纸底，白字必须靠黑描边才立得住，色块会挡住 UI。
SUB_STYLE = (
    "FontName=PingFang SC,FontSize=13,PrimaryColour=&HFFFFFF&,"
    "OutlineColour=&H000000&,BorderStyle=1,Outline=1.4,Shadow=0.8,"
    "Bold=1,Alignment=2,MarginV=26,MarginL=80,MarginR=80"
)

GAP = 0.2        # 相邻字幕之间的空隙（秒）
MIN_SPAN = 0.8   # 单条字幕最短停留（秒），避免过短句一闪而过
FPS = 30         # 统一输出帧率（拼接要求各段参数一致）


def seg_num(key: str) -> str:
    return key[3:]  # "seg01" -> "01"


def find_clip(num: str) -> Path | None:
    for ext in ("mp4", "mov", "mkv"):
        p = RAW / f"demo_{num}.{ext}"
        if p.exists():
            return p
    return None


def find_voice(key: str) -> Path | None:
    p = VOICE / f"{key}.mp3"
    return p if p.exists() else None


def media_duration(path: Path) -> float:
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
    sec = max(sec, 0.0)
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = int(sec % 60)
    ms = int(round((sec - int(sec)) * 1000))
    if ms >= 1000:          # 四舍五入进位，避免 999.7ms -> 1000ms 的非法时间
        ms -= 1000
        s += 1
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def build_entries(text: str, duration: float,
                  offset: float = 0.0) -> list[tuple[float, float, str]]:
    """按整句字数占比分配时长 —— 等分会让长句字幕滞后、短句空留，读起来对不上口型。"""
    sents = split_sentences(text) or [text]
    weights = [max(len(s), 1) for s in sents]
    total = sum(weights)
    entries: list[tuple[float, float, str]] = []
    cursor = offset
    for sent, w in zip(sents, weights):
        span = duration * w / total
        start = cursor
        end = max(start + span - GAP, start + MIN_SPAN)
        cursor = start + span
        entries.append((start, end, sent))
    return entries


def write_srt(path: Path, entries: list[tuple[float, float, str]]) -> Path:
    lines = []
    for i, (start, end, sent) in enumerate(entries):
        lines.append(f"{i + 1}")
        lines.append(f"{srt_time(start)} --> {srt_time(end)}")
        lines.append(sent)
        lines.append("")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def fit_plan(vd: float, na: float, lead: float,
             max_speed: float, min_speed: float, fit: bool):
    """求「视频变速倍数 / 定格时长 / 成片段长」。

    目标是让画面长度追上配音长度（lead + na），配音不动，只动画面：
      k = vd / (lead + na)，把 k 夹在 [min_speed, max_speed] 内。
      夹完还够不着 → 定格最后一帧补足；夹完还超长 → 尾部留静音（画外音结束后画面继续）。

    ⚠️ 定格时长固定多给 1 帧：fps 归一到 30 后画面长度会量化到帧边界，
    若正好比音轨短几毫秒，拼接时视频帧会「跳」到下一段，整片错位。
    """
    want = lead + na                       # 期望段长 = 配音（含前导）长度
    eps = 1.0 / FPS
    if not fit or want <= 0:
        k, vlen = 1.0, vd
    else:
        k = min(max(vd / want, min_speed), max_speed)
        vlen = vd / k
    out_len = max(vlen, want) + eps        # 画面超长 → 尾部静音；画面不足 → 补帧
    freeze = out_len - vlen
    return k, freeze, out_len, want


def render(clip: Path, voice: Path, srt_rel: str, k: float, freeze: float,
           total: float, lead: float, num: str) -> Path:
    """一段成片：[视频变速] + [定格] + [烧字幕]，配音延迟 lead 秒后铺上，裁到 total。

    ⚠️ 滤镜顺序不能改：setpts → fps → tpad。
    setpts 之后流仍是变帧率，此时 tpad 按输入帧率给克隆帧打时间戳，几乎补不出帧
    （实测 setpts,tpad,fps 只得到 8.5s；setpts,fps,tpad 才得到 13.8s）。
    """
    dst = OUT / f"out_{num}.mp4"

    vf = [f"setpts=PTS/{k:.6f}", f"fps={FPS}"]
    if freeze > 0.001:
        vf.append(f"tpad=stop_mode=clone:stop_duration={freeze:.3f}")
    vf.append(f"subtitles={srt_rel}:force_style='{SUB_STYLE}'")

    af = f"adelay={int(round(lead * 1000))}:all=1,apad"

    subprocess.run(
        [FFMPEG, "-y", "-i", str(clip), "-i", str(voice),
         "-filter_complex", f"[0:v]{','.join(vf)}[v];[1:a]{af}[a]",
         "-map", "[v]", "-map", "[a]",
         "-t", f"{total:.3f}",
         "-c:v", "libx264", "-preset", "medium", "-crf", "20",
         "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
         "-movflags", "+faststart", str(dst)],
        check=True, cwd=HERE,          # 相对路径的 SRT 依赖 cwd
    )
    return dst


def concat(nums: list[str]) -> Path:
    files = [OUT / f"out_{n}.mp4" for n in nums if (OUT / f"out_{n}.mp4").exists()]
    if not files:
        print("[gen_subs] 没有可合并的 out_*.mp4，先跑 --burn/--all")
        return Path()
    lst = HERE / "filelist.txt"
    lst.write_text("\n".join(f"file '{f}'" for f in files), encoding="utf-8")
    dst = HERE / "final_demo.mp4"
    subprocess.run(
        [FFMPEG, "-y", "-f", "concat", "-safe", "0", "-i", str(lst),
         "-c", "copy", str(dst)],
        check=True, cwd=HERE,
    )
    lst.unlink(missing_ok=True)
    return dst


def mmss(s: float) -> str:
    return f"{int(s) // 60}:{int(s) % 60:02d}"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--burn", action="store_true", help="渲染分段成片（变速贴合 + 烧字幕 + 铺配音）")
    ap.add_argument("--concat", action="store_true", help="渲染后合并为 final_demo.mp4")
    ap.add_argument("--all", action="store_true", help="等价于 --burn --concat")
    ap.add_argument("--only", type=int, default=0, help="只处理指定段号（试看用）")
    ap.add_argument("--fit", dest="fit", action="store_true", default=True,
                    help="视频变速贴合配音（默认开）")
    ap.add_argument("--no-fit", dest="fit", action="store_false",
                    help="视频完全不动，配音铺上去（画面偏长的段会留静音）")
    ap.add_argument("--max-speed", type=float, default=5.0,
                    help="视频加速上限（默认 5.0 倍；本片第 1/6 段需 4.0/4.8 倍才不留静音）")
    ap.add_argument("--min-speed", type=float, default=0.85, help="视频减速下限（默认 0.85 倍）")
    ap.add_argument("--lead", type=float, default=0.35, help="配音相对段首的延迟秒数（默认 0.35）")
    ap.add_argument("--default-dur", type=float, default=60.0,
                    help="配音与片段都缺时的占位时长（秒），仅用于预览 SRT")
    args = ap.parse_args()

    if args.all:
        args.burn = args.concat = True

    merged: list[tuple[float, float, str]] = []
    merged_cursor = 0.0
    done: list[str] = []
    rows: list[tuple] = []

    for key, text in SEGMENTS.items():
        num = seg_num(key)
        if args.only and int(num) != args.only:
            continue
        clip = find_clip(num)
        voice = find_voice(key)

        vd = media_duration(clip) if clip else 0.0
        na = media_duration(voice) if voice else 0.0

        if not clip and not voice:
            na = args.default_dur
            print(f"[gen_subs] {key}: ⚠️ 无配音也无片段，用占位 {na:.0f}s 预览")
        elif not voice:
            na = vd
            print(f"[gen_subs] {key}: ⚠️ 缺配音，字幕改按片段时长铺")

        # 1) 字幕：时间轴 = 配音实测时长
        entries = build_entries(text, na, offset=args.lead)
        write_srt(SUBS / f"{key}.srt", entries)

        # 2) 贴合
        k, freeze, total, want = fit_plan(vd, na, args.lead,
                                          args.max_speed, args.min_speed, args.fit)
        dead = max(0.0, total - (args.lead + na))
        note = []
        if k > 1.005:
            note.append(f"加速{k:.2f}x")
        elif k < 0.995:
            note.append(f"减速{k:.2f}x")
        if freeze > 0.05:
            note.append(f"定格{freeze:.1f}s")
        if dead > 0.5:
            note.append(f"尾部静音{dead:.1f}s")
        rows.append((num, vd, na, k, freeze, total, dead, " ".join(note) or "原速贴合"))

        merged.extend(build_entries(text, na, offset=merged_cursor + args.lead))
        merged_cursor += total

        # 3) 渲染
        if args.burn:
            if not (clip and voice):
                print(f"[gen_subs] {key}: ⚠️ 跳过渲染（缺片段或缺配音）")
                continue
            dst = render(clip, voice, f"{SUBS.name}/{key}.srt", k, freeze, total,
                         args.lead, num)
            done.append(num)
            print(f"[gen_subs] {key}: -> {dst.name}  视频{vd:.1f}s 配音{na:.1f}s "
                  f"→ 段长{total:.1f}s  {' '.join(note) or '原速'}")

    write_srt(SUBS / "all.srt", merged)

    print()
    if args.burn:
        print(f"{'#':>3} {'录屏s':>7} {'配音s':>7} {'倍数':>6} {'定格s':>6} {'段长s':>7} {'静音s':>6}  处理")
        for num, vd, na, k, freeze, total, dead, note in rows:
            print(f"{num:>3} {vd:>7.1f} {na:>7.1f} {k:>6.2f} {freeze:>6.1f} "
                  f"{total:>7.1f} {dead:>6.1f}  {note}")
    print(f"[gen_subs] 整片 {mmss(merged_cursor)}（{merged_cursor:.0f}s）"
          f"{'，已渲染 %d 段' % len(done) if done else ''}，字幕 -> all.srt")

    if args.concat and done:
        final = concat(done)
        if final:
            print(f"[gen_subs] 合并完成 -> {final.name}"
                  f"（{mmss(media_duration(final))}）")


if __name__ == "__main__":
    main()
