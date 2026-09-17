# Scripts

Every script is a single, runnable shell file under `bin/`. They share
helpers via `lib/common.sh`. Run them in pipeline order; see [PIPELINE.md](PIPELINE.md).

## `bin/render-shot.sh`

Render one freeze-frame MP4 from one PNG.

```
bin/render-shot.sh <input.png> <duration_seconds> <output.mp4>
```

| Arg | Required | Notes |
|-----|----------|-------|
| `input.png` | yes | Frame from ComfyUI |
| `duration_seconds` | yes | > 0; from `align-segment.json` |
| `output.mp4` | yes | Will be overwritten (`-y`) |

**Exit codes:** 0 ok · 1+ on any ffmpeg failure or missing tool.

## `bin/stitch-shots.sh`

Concatenate per-shot MP4s into one video (no re-encode).

```
bin/stitch-shots.sh <concat_list.txt> <output.mp4>
```

`concat_list.txt` follows the [ffmpeg concat demuxer](https://ffmpeg.org/ffmpeg-formats.html#concat) format:

```
file '/abs/path/shot_0001.mp4'
file '/abs/path/shot_0002.mp4'
```

The orchestrator writes this file for you from `durations.tsv`.

## `bin/mix-audio.sh`

Mix narration with an optional music bed.

```
bin/mix-audio.sh <narration.mp3> <music.ogg|-> <output.wav> [music_volume_linear]
```

| Arg | Notes |
|-----|-------|
| `narration.mp3` | from `qwen3-tts` |
| `music.ogg` | from external music library; pass `-` for narration-only |
| `output.wav` | 48 kHz, 2ch, PCM-24 |
| `music_volume_linear` | optional, default `0.18` (≈ −15 dB) |

## `bin/normalize-loudness.sh`

EBU R128 two-pass loudness normalization. Output is 48/2/PCM-24 wav.

```
bin/normalize-loudness.sh <input.wav> <output.wav>
```

Targets (overridable via env): `LOUDNORM_I=-16`, `LOUDNORM_TP=-1.5`, `LOUDNORM_LRA=11`.

## `bin/burn-captions.sh`

Burn an SRT into the video (default) or mux as soft sub (`--soft`).

```
bin/burn-captions.sh <input.mp4> <captions.srt> <output.mp4> [--soft]
```

## `bin/render-master.sh`

The orchestrator. Runs every stage in order.

```
bin/render-master.sh <name> <master.mp4> [inputs_dir] [outputs_dir]
```

After completion the run directory at `outputs/<name>/` contains every
intermediate file plus the final `master.mp4` at the path you passed.

## `scripts/check`

Local CI. Runs `shellcheck` against `bin/` and validates every
`inputs/*.json` against `schemas/align-segment.schema.json`. Invoked by
`githooks/pre-push`.

```
scripts/check
```

## `lib/common.sh`

**Source me, never run me.** Provides:

- Constants: `FPS`, `X264_PRESET`, `X264_CRF`, `X264_TUNE`, `LOUDNORM_*`, `AUDIO_CODEC`, `AUDIO_BITRATE`.
- Logging: `log`, `stage`, `die`.
- Tool presence: `need`, `require_tools`.
- Validation: `require_file`, `require_dir`.
- Layout: `ensure_layout`, `write_durations_tsv`.
