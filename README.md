# project-basic-logic

The deterministic finisher for the video pipeline. Bash + FFmpeg.

## What it does

Takes:

- One narration audio file from [`qwen3-tts`](https://github.com/3n8/qwen3-tts)
- One alignment JSON from [`qwen3-aligner`](https://github.com/3n8/qwen3-aligner) (per-word start/end)
- One ordered set of PNG stills from ComfyUI (one per shot)
- One music cue (optional)
- One SRT caption file

Produces:

- One reproducible `master.mp4` per video.

Two runs of the same inputs produce the same output. That is the test of "deterministic."

## Quick start

```sh
# Inputs go in inputs/ (gitignored):
#   inputs/align-segment.json    — word/phrase timestamps
#   inputs/frames/shot_NNNN.png  — one PNG per shot
#   inputs/narration.mp3         — voice track
#   inputs/music.ogg             — optional bed
#   inputs/captions.srt          — optional soft-subs

# Run the orchestrator with a name and a master file path:
bin/render-master.sh "ep001" outputs/ep001/master.mp4

# Outputs:
#   outputs/ep001/shot_NNNN.mp4      ← per-shot freeze-frame clips
#   outputs/ep001/video.mp4          ← stitched video
#   outputs/ep001/audio.wav          ← mixed + loudness-normalized
#   outputs/ep001/captions.srt       ← echoed captions
#   outputs/ep001/master.mp4         ← final
```

## Prerequisites

| Tool | Version | Why |
|------|---------|-----|
| bash | 5+ | All `bin/` scripts use `set -euo pipefail` |
| ffmpeg | 9.0+ | The whole point |
| jq | 1.6+ | Read aligner JSON into per-shot durations |
| shellcheck | 0.9+ | Run by `scripts/check` |

On Hel, all four are already installed. On macOS: `brew install ffmpeg jq shellcheck bash`.

## Pipeline at a glance

```
[ qwen3-tts narration.mp3 ]    [ qwen3-aligner JSON ]    [ ComfyUI frames ]
                \                       |                       /
                 \                      |                      /
                  +------ bin/render-master.sh ----------------+
                                       |
                                       v
                                 master.mp4  (deterministic)
```

Full pipeline map: [docs/PIPELINE.md](docs/PIPELINE.md).

## Scripts

Read [docs/SCRIPTS.md](docs/SCRIPTS.md) for the per-script contract (inputs, outputs, exit codes).

## License

MIT — see [LICENSE](LICENSE).

## Companion repos

- [`3n8/qwen3-tts`](https://github.com/3n8/qwen3-tts) — narration audio
- [`3n8/qwen3-aligner`](https://github.com/3n8/qwen3-aligner) — word/phrase timestamps
- ComfyUI (Hel-hosted) — illustrated stills
