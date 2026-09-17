#!/usr/bin/env python3
"""Group word-level aligner JSON into semantic shot cues.

Success gates (prefix): median 2.0-4.5s, <5% of shots <1.0s,
at least one 8-25s hold if the audio is long enough, shot count << word count,
sum of shot spans equals audio duration ±0.10s.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: group-cues.py <align-words.json> <cues.json>")
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    data = json.loads(src.read_text())
    words = []
    for seg in data["segments"]:
        text = str(seg.get("text", "")).strip()
        start = float(seg["start"])
        end = float(seg["end"])
        if end < start:
            start, end = end, start
        if end == start:
            end = start + 0.04
        if not text:
            continue
        words.append({"text": text, "start": start, "end": end})

    audio_dur = float(data.get("duration") or words[-1]["end"])

    # Merge tiny leftovers into previous after sentence/pause packing.
    shots = pack(words)
    shots = merge_short(shots, min_s=1.5)
    # Snap first start to 0 and last end to audio duration so video matches narration.
    if shots:
        shots[0]["start"] = 0.0
        shots[-1]["end"] = audio_dur
        for i in range(1, len(shots)):
            shots[i]["start"] = shots[i - 1]["end"]

    out_segs = []
    for i, s in enumerate(shots, 1):
        out_segs.append({
            "id": f"shot_{i:04d}",
            "text": s["text"],
            "start": round(s["start"], 3),
            "end": round(s["end"], 3),
            "score": None,
        })
    out = {
        "model": data.get("model"),
        "language": data.get("language"),
        "duration": audio_dur,
        "source_words": len(words),
        "segments": out_segs,
    }
    dst.write_text(json.dumps(out, indent=2) + "\n")
    durs = [s["end"] - s["start"] for s in out_segs]
    durs_sorted = sorted(durs)
    n = len(durs)
    med = durs_sorted[n // 2]
    print(json.dumps({
        "shots": n,
        "words": len(words),
        "median_s": round(med, 3),
        "min_s": round(min(durs), 3),
        "max_s": round(max(durs), 3),
        "pct_lt_1s": round(100 * sum(d < 1 for d in durs) / n, 1),
        "holds_8_25": sum(8 <= d <= 25 for d in durs),
        "sum_s": round(sum(durs), 3),
        "audio_s": audio_dur,
        "out": str(dst),
    }))


def pack(words: list[dict]) -> list[dict]:
    shots: list[dict] = []
    cur: list[dict] = []

    def flush() -> None:
        nonlocal cur
        if not cur:
            return
        shots.append({
            "text": " ".join(w["text"] for w in cur),
            "start": cur[0]["start"],
            "end": cur[-1]["end"],
        })
        cur = []

    for i, w in enumerate(words):
        cur.append(w)
        dur = cur[-1]["end"] - cur[0]["start"]
        nxt = words[i + 1] if i + 1 < len(words) else None
        gap = (nxt["start"] - w["end"]) if nxt else 0.0
        punct = w["text"].rstrip().endswith((".", "?", "!"))
        comma = w["text"].rstrip().endswith((",", ";", ":"))
        if nxt is None:
            flush()
            continue
        # Prefer sentence boundaries once we have ~2s.
        if punct and dur >= 2.0:
            flush()
            continue
        # Pause between claims.
        if gap >= 0.30 and dur >= 2.0:
            flush()
            continue
        # Split long sentences on commas after ~3s.
        if comma and dur >= 3.0:
            flush()
            continue
        # Hard cap so we never hold a whole paragraph as one freeze.
        if dur >= 8.5:
            flush()
            continue
    return shots


def merge_short(shots: list[dict], min_s: float) -> list[dict]:
    if not shots:
        return shots
    out: list[dict] = []
    for s in shots:
        dur = s["end"] - s["start"]
        if out and dur < min_s:
            out[-1]["end"] = s["end"]
            out[-1]["text"] = (out[-1]["text"] + " " + s["text"]).strip()
        else:
            out.append(dict(s))
    # If the first shot is still tiny, merge forward.
    if len(out) >= 2 and out[0]["end"] - out[0]["start"] < min_s:
        nxt = out.pop(1)
        out[0]["end"] = nxt["end"]
        out[0]["text"] = (out[0]["text"] + " " + nxt["text"]).strip()
    return out


if __name__ == "__main__":
    main()
