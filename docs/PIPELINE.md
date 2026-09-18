# Pipeline

```
[ qwen3-tts:    narration.mp3  ]   [ qwen3-aligner: align-segment.json ]   [ ComfyUI: shot_NNNN.png ]
                  \                       |                                    /
                   \                      |                                   /
                    +------- bin/render-master.sh ----------------------------+
                                              |
   inputs/                  pipeline scripts                 outputs/
   ──────────────           ───────────────────              ──────────────────
   align-segment.json   →   bin/render-shot.sh          →   shot_NNNN.mp4
   frames/shot_NNNN.png →   bin/stitch-shots.sh         →   video.mp4
   narration.mp3        →   bin/mix-audio.sh            →   audio_raw.wav
   music.ogg           ↘    bin/normalize-loudness.sh   →   audio.wav
   captions.srt             bin/burn-captions.sh        →   captioned.mp4
                            bin/render-master.sh         →   master.mp4
```

## Stages

1. **render-shot** — one PNG + one duration → one MP4 freeze-frame clip.
   Done per-shot, in parallel if you want. Per-shot durations come from
   `align-segment.json` via `jq`.

2. **stitch-shots** — concat all per-shot MP4s into a single video using
   ffmpeg's `-c:v copy` (lossless) concat demuxer. No re-encode at this
   stage; that's deliberate so the stitched file is byte-stable.

3. **mix-audio** — `amix` filter, narration at full level + music at
   0.18× linear (≈ −15 dB). Output is 48 kHz / 2ch / PCM-24 wav.

4. **normalize-loudness** — EBU R128 two-pass (`loudnorm` with
   `linear=true`). Target I=-16, TP=-1.5, LRA=11. Pass 1 measures,
   pass 2 applies. Output is again 48/2/PCM24.

5. **burn-captions** — if `captions.srt` exists, mux into video. Burn-in
   is the default (image-rendered text); `--soft` keeps SRT as a separate
   track.

6. **render-master** (orchestrator) — runs 1–5 in order, plus the final
   mux: video + audio + optional captions.

## Determinism

Every stage above has its inputs as files on disk. Every output is a
single file with a fixed name. Same inputs → same outputs:

- `align-segment.json` does not change between runs of the same video.
- `frames/shot_NNNN.png` does not change unless ComfyUI re-renders.
- `narration.mp3` does not change unless qwen3-tts re-synthesises.
- For pure determinism we render once and **don't re-render**. If the
  inputs change, re-run the orchestrator; expect a new output bit-for-bit.

The encoder (`libx264 -preset slow -tune stillimage`) is deterministic on
identical inputs. `loudnorm` measured values are deterministic on
identical input audio.

## Outside the master path

- `bin/group-cues.sh` — deterministic rule engine that packs a word-level
  aligner JSON into shot cues. Not invoked by `render-master.sh`; used to
  build a cuttable length from an aligner JSON alone.
- `bin/make-placeholder-frames.sh` — deterministic 1920x1080 PNG per cue
  for running the pipeline before approved frames exist. Not invoked by
  `render-master.sh`.
