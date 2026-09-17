#!/usr/bin/env python3
"""One uniquely coloured 1920x1080 PNG per cue, named for write_durations_tsv."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

PALETTE = [
    "#1b1b1b", "#3d2b1f", "#2f4f4f", "#4a3728", "#1f3b4d",
    "#5c4033", "#2c3e50", "#3b2f2f", "#4b5320", "#2e1a47",
    "#3e2723", "#1a3a3a", "#4a1942", "#243447",
]


def jq_shot_name(index0: int) -> str:
    s = ("0000" + str(index0 + 1))[-4:]
    return f"shot_{s}"


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make-placeholder-frames.py <cues.json> <frames_dir>")
    cues = json.loads(Path(sys.argv[1]).read_text())
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    font = Path("/usr/share/fonts/TTF/DejaVuSans.ttf")
    n = 0
    for i, _seg in enumerate(cues["segments"]):
        name = jq_shot_name(i)
        color = PALETTE[i % (len(PALETTE) - 1)]
        dest = out / f"{name}.png"
        cmd = [
            "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", f"color=c={color}:s=1920x1080:d=1",
        ]
        if font.exists():
            cmd += ["-vf", f"drawtext=fontfile={font}:text='{name}':fontcolor=white:fontsize=64:x=80:y=80"]
        cmd += ["-frames:v", "1", str(dest)]
        subprocess.check_call(cmd)
        n += 1
    print(json.dumps({"frames": n, "dir": str(out)}))


if __name__ == "__main__":
    main()
