"""生成演示视频 7 段中文配音 (Edge TTS, 免费无需 Key)。

旁白文案单一事实源：narration.md（可直接编辑，按 '## N ...' 分段）。
改完文案后运行本脚本，即重新生成 voice/seg01.mp3 ... seg07.mp3。
字幕脚本 gen_subs.py 复用同一份文本，自动按句切片烧入。

用法:
  /Users/annilq/.workbuddy/binaries/python/envs/default/bin/python gen_voice.py
"""
import re
import subprocess
import sys
from pathlib import Path

VOICE = "zh-CN-XiaoxiaoNeural"
HERE = Path(__file__).resolve().parent
NARRATION = HERE / "narration.md"
OUT = HERE / "voice"
OUT.mkdir(parents=True, exist_ok=True)


def load_segments(md: Path) -> dict[str, str]:
    """从 narration.md 解析段落。格式：以 '## N ...' 标题分段，N 为段号。"""
    text = md.read_text(encoding="utf-8")
    parts = re.split(r"(?m)^##\s+(\d+)[^\n]*\n", text)
    segs: dict[str, str] = {}
    for i in range(1, len(parts), 2):
        num = int(parts[i])
        body = re.sub(r"\s+", " ", parts[i + 1]).strip()
        if body:
            segs[f"seg{num:02d}"] = body
    return segs


def main() -> None:
    segs = load_segments(NARRATION)
    if not segs:
        print("[gen_voice] 未在 narration.md 解析到任何段落，请检查标题格式 '## 1 ...'")
        sys.exit(1)
    for name, text in segs.items():
        out = OUT / f"{name}.mp3"
        print(f"[gen_voice] {name} -> {out}")
        subprocess.run(
            [sys.executable, "-m", "edge_tts",
             "--voice", VOICE, "--text", text, "--write-media", str(out)],
            check=True,
        )
    print(f"[gen_voice] done. {len(segs)} files in {OUT}")


if __name__ == "__main__":
    main()
