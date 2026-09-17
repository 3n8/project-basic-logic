#!/usr/bin/env python3
"""Coalesce word-level aligner JSON into ~2s SRT captions."""
from __future__ import annotations

import json
import sys
from pathlib import Path

TARGET = 2.0
MAX_S = 2.8


def fmt(t: float) -> str:
    if t < 0:
        t = 0.0
    ms = int(round(t * 1000))
    h, ms = divmod(ms, 3600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make-srt.py <align-words.json> <out.srt>")
    data = json.loads(Path(sys.argv[1]).read_text())
    words = data["segments"]
    cues = []
    cur = []
    for w in words:
        cur.append(w)
        dur = cur[-1]["end"] - cur[0]["start"]
        punct = str(w.get("text", "")).rstrip().endswith((".", "?", "!"))
        if dur >= TARGET and (punct or dur >= MAX_S):
            cues.append(cur)
            cur = []
    if cur:
        if cues and (cur[-1]["end"] - cur[0]["start"]) < 1.0:
            cues[-1].extend(cur)
        else:
            cues.append(cur)
    lines = []
    for i, c in enumerate(cues, 1):
        start = float(c[0]["start"])
        end = float(c[-1]["end"])
        if end <= start:
            end = start + 0.04
        text = " ".join(str(x.get("text", "")).strip() for x in c)
        lines.append(f"{i}\n{fmt(start)} --> {fmt(end)}\n{text}\n")
    Path(sys.argv[2]).write_text("\n".join(lines) + "\n")
    durs = [float(c[-1]["end"]) - float(c[0]["start"]) for c in cues]
    mean = sum(durs) / len(durs) if durs else 0
    print(json.dumps({
        "cues": len(cues),
        "mean_s": round(mean, 3),
        "min_s": round(min(durs), 3) if durs else 0,
        "max_s": round(max(durs), 3) if durs else 0,
        "out": sys.argv[2],
    }))


if __name__ == "__main__":
    main()
