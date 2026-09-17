# project-basic-logic — agents

This file is for humans and for new AI sessions. Read it before changing the repo.

## Goal

**project-basic-logic is the deterministic finisher for the video pipeline.**

Narration audio is rendered by [`qwen3-tts`](https://github.com/3n8/qwen3-tts).
Visual frames are produced by ComfyUI on Hel.
[`qwen3-aligner`](https://github.com/3n8/qwen3-aligner) (sibling container, same base) ties them together with word/phrase timestamps.
**This repo turns those known inputs into one reproducible `master.mp4` per video via FFmpeg.**

It is not a creative layer. It is not a server. It is a set of shell scripts + a JSON schema contract + a `scripts/check` that runs before push.

## Stack (bottom to top)

1. **Bash 5+** — every script is a runnable file under `bin/`. Same exit semantics, same flags.
2. **FFmpeg `n9.0.1`+** — `libx264` for video, `aac` for audio, `loudnorm` for EBU R128. Output is `mp4`/`mov`.
3. **jq** — JSON ↔ env, used to read `align-segment.json` into per-shot durations.
4. **`scripts/check`** — runs `shellcheck` against `bin/`, validates every `inputs/*.json` against `schemas/align-segment.schema.json`.

There is no Python, no Node, no Docker, no GPU at runtime. Plain shell + FFmpeg keeps the finisher reproducible for years.

## How to work

- **One script per operation.** Each `bin/<verb>-<noun>.sh` does exactly one stage of the pipeline. The order in AGENTS.md is the order to call them.
- **Inputs come from upstream.** Narration is `qwen3-tts` output. Frames are ComfyUI output. Timestamps are `qwen3-aligner` output. We do not produce them here. We do not invert them.
- **Output is one file per script.** Each script is idempotent on identical inputs. Two runs of the same script on the same inputs produce the same output (modulo the encoder's `-preset` determinism; `x264 --preset slow -tune stillimage` is stable enough).
- **No silent failures.** Every script begins with `set -euo pipefail`, logs `[stage]` lines to stderr, and exits non-zero on any error.
- **`scripts/check` runs before push.** This repo sets `git config core.hooksPath githooks`. The hook runs `scripts/check`. Do not hand the human a checklist.
- **Render what you get.** No filters that "improve" the drawings. No automatic color tweaks. No lat/long EIS. We render what we get. The cutter only cuts.

## What is NOT here

- No joint audio-video (motion-from-audio) generation. Drawings only.
- No automatic frame interpolation beyond `fps=24` playback of stills.
- No per-shot pixel comparison. Visuals are approved upstream, not here.
- No music composition. Music is an external input.
- No upload or publish steps. Final delivery is outside the repo.
- No AI/Eve/Lilith calls in bin/. Binaries are dumb.

## Layout

```
bin/                    shell scripts (one per operation, all sourceable)
lib/common.sh           shared helpers; sourced, never run directly
schemas/                JSON Schema for aligner output + per-shot renders
inputs/                 gitignored — drop align-segment.json + frame PNGs here
outputs/                gitignored — produced master files
scripts/check           local CI; runs shellcheck + jsonschema validation
githooks/pre-push       invokes scripts/check on git push
opencode.json           enables the ponytail style plugin (per `envim`)
docs/PIPELINE.md        visual + textual pipeline map
docs/SCRIPTS.md         each bin/ script's contract
```

## Pipeline order

1. `bin/render-shot.sh`        (per-shot PNG → MP4 at known duration)
2. `bin/stitch-shots.sh`       (concat per-shot MP4s → one video)
3. `bin/mix-audio.sh`          (narration + music → stereo mix)
4. `bin/normalize-loudness.sh` (mix → EBU R128 normalized)
5. `bin/burn-captions.sh`      (video + SRT → captioned video)
6. `bin/render-master.sh`      (orchestrator: runs 1–5 in the right order)

## When this repo moves upstream

- Aligner JSON contract changes → update `schemas/align-segment.schema.json` and any jq filters in `bin/`.
- Encoder swaps → update the `FFMPEG_*` constants in `lib/common.sh`. One place.
- Output container changes → `bin/render-master.sh` is the only orchestrator.
