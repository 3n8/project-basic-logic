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
| awk | gawk 4+ | Used by `make-srt.sh` and `group-cues.sh` for byte-identical JSON formatting |
| shellcheck | 0.9+ | Run by `scripts/check` |

On Hel, all five are already installed. On macOS: `brew install ffmpeg jq shellcheck bash gawk`.

There is no Python anywhere in `bin/` — `make-srt.sh`, `group-cues.sh`, and
`make-placeholder-frames.sh` are bash ports of former `.py` helpers, byte-identical
to the originals.

## Dev utilities outside the master path

`bin/group-cues.sh` and `bin/make-placeholder-frames.sh` are deterministic dev
utilities, not pipeline stages. `render-master.sh` never calls them.

- `group-cues.sh` — aligns words to cue boundaries. Shot boundaries for a real
  video are approved upstream, before ComfyUI renders one PNG per shot; this
  rule engine exists so a full-length cut can be built and inspected from an
  aligner JSON alone.
- `make-placeholder-frames.sh` — labelled 1920x1080 stills, one per cue, for
  running the pipeline before the approved frame set exists.

Both are byte-identical to the retired Python scripts they replace.

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

## Makefile

Thin wrappers, if you don't want to type `bin/render-master.sh` directly:

```sh
make render NAME=ep001            # bin/render-master.sh ep001 outputs/ep001/master.mp4 inputs outputs
make dry-run NAME=ep001           # print the planned pipeline, run nothing
make check                        # scripts/check
make smoke                        # tiny fixture, end to end, < 90 s
make clean NAME=ep001             # remove outputs/ep001/
make help
```

## Dry run

Every script in `bin/` accepts `--dry-run` (or `DRY_RUN=1`). It prints the exact
ffmpeg command it would run and writes no media, so you can inspect a full
pipeline before committing to a long encode:

```sh
bin/render-master.sh --dry-run ep001 outputs/ep001/master.mp4
```

## Smoke test

`scripts/smoke` generates a 3-shot / 6-second fixture with
`bin/make-smoke-fixture.sh` (frames are produced with ffmpeg, narration is a quiet
tone) and runs the whole pipeline against it. `inputs/` is gitignored, so the
fixture is generated rather than committed. Budget: 90 seconds; measured: ~1 second.

```sh
make smoke      # or: scripts/smoke
```

## AMD / ROCm hosts

The standalone `HSA_OVERRIDE_GFX_VERSION` environment variable matters on AMD hosts
that run ROCm workloads: recent consumer GPUs are not always recognised by the ROCm
runtime, and `HSA_OVERRIDE_GFX_VERSION` is how you tell it to treat the card as a
supported one. Setting it to the wrong value makes GPU workloads fail or fall back
to CPU.

**This repo is not one of those workloads.** `project-basic-logic` is bash + FFmpeg
with no GPU code, so it must never require or set `HSA_OVERRIDE_GFX_VERSION` — if a
finisher run only works with it set, something else on the host is wrong. The
variable belongs to the upstream GPU services on the same machine (`qwen3-tts`,
`qwen3-aligner`, ComfyUI); set it there, not here.

## License

MIT — see [LICENSE](LICENSE).

## Companion repos

- [`3n8/qwen3-tts`](https://github.com/3n8/qwen3-tts) — narration audio
- [`3n8/qwen3-aligner`](https://github.com/3n8/qwen3-aligner) — word/phrase timestamps
- ComfyUI (Hel-hosted) — illustrated stills
