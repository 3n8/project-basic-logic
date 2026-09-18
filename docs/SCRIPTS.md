# Scripts

Every script is a single, runnable shell file under `bin/`. They share
helpers via `lib/common.sh`. Run them in pipeline order; see [PIPELINE.md](PIPELINE.md).

Every `bin/*.sh` script accepts `--dry-run` (or `DRY_RUN=1`): it prints the exact
ffmpeg command it would run and writes no media. In dry-run the downstream
`require_file` checks are relaxed, because intermediate files were never written.

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

Burn an SRT into the video (default) or mux as soft sub (`--soft`). Called by
`render-master.sh`, which picks the mode; run it directly only to redo this step alone.

```
bin/burn-captions.sh [--dry-run] <input.mp4> <captions.srt> <output.mp4> [--soft]
```

## `bin/render-master.sh`

The orchestrator. Runs every stage in order.

```
bin/render-master.sh [--dry-run] [--captions burn|soft|off] <name> <master.mp4> [inputs_dir] [outputs_dir]
```

| Flag | Default | Notes |
|------|---------|-------|
| `--dry-run` | off | Print every planned ffmpeg command, write no media (also `DRY_RUN=1`) |
| `--captions burn\|soft\|off` | `burn` | How to handle `captions.srt`. Also settable via the `CAPTIONS` env var; the flag wins. An invalid value aborts. Mode is ignored when there is no `captions.srt`. |

Caption modes: **`burn`** draws the text into the picture (always visible, the Shorts
look); **`soft`** attaches a switchable subtitle track next to the audio (long-form);
**`off`** leaves the master without subtitles.

After completion the run directory at `outputs/<name>/` contains every
intermediate file plus the final `master.mp4` at the path you passed.

## `bin/extract-segment-duration.sh`

Aligner JSON → `durations.tsv` (`shot_NNNN<TAB>seconds`), the table the
orchestrator consumes.

```
bin/extract-segment-duration.sh <align-segment.json> [out.tsv]
```

`out.tsv` defaults to `inputs/durations.tsv`.

## `bin/make-srt.sh`

Coalesce word-level aligner JSON into SRT captions (sub-second precision,
words grouped into ~2 s cues), in bash + jq + awk.

```
bin/make-srt.sh <align-words.json> <out.srt>
```

Emits a one-line JSON summary on stderr. Replaced `bin/make-srt.py`, which it
matches byte for byte.

## `bin/group-cues.sh`

Pack word-level aligner JSON into semantic shot cues (sub-second precision,
sentence / pause / comma / 8.5 s hard-cap boundary rules), in bash + jq + awk.

```
bin/group-cues.sh <align-words.json> <cues.json>
```

Emits a one-line JSON summary on stderr. Replaced `bin/group-cues.py`, which
it matches byte for byte on `inputs/reference/{prefix,full}_align_words.json`.
Supports `--dry-run`.

Documented deviation from the Python source: a segment whose `text` is JSON
`null` is skipped (Python's `str(None)` would have kept the literal word
`None`; the bash port matches the `if not text: continue` semantic after
`.strip()` instead). Missing `text` keys are also skipped, matching Python.

## `bin/make-placeholder-frames.sh`

One uniquely coloured 1920x1080 PNG per cue, named `shot_NNNN` (1-based) so
`write_durations_tsv` can re-discover them. The colour index is `i % 13`
— the 14th palette entry is intentionally unreachable, matching the Python
source.

```
bin/make-placeholder-frames.sh <cues.json> <frames_dir>
```

Emits a one-line JSON summary on stderr. Replaced `bin/make-placeholder-frames.py`,
which it matches byte for byte on the full reference cue set (40 PNGs).
Supports `--dry-run`.

## `bin/make-smoke-fixture.sh`

Generate the end-to-end fixture used by `scripts/smoke` (3 shots × 2 s, quiet
tone narration, 320×180 frames). `inputs/` is gitignored, so this is generated
rather than committed.

```
bin/make-smoke-fixture.sh [dir]      # default: inputs/smoke
```

## `scripts/smoke`

Build the fixture and run `bin/render-master.sh` against it end to end, failing if
the result exceeds 90 seconds. Uses `X264_PRESET=veryfast` (override with
`SMOKE_X264_PRESET`) so the plumbing, not the encoder, is what is tested.

```
scripts/smoke
```

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
- Logging: `log`, `stage`, `die`, `wrote`.
- Tool presence: `need`, `require_tools`.
- Dry run: `dry_run_enabled`, `run`, `make_dir`, `parse_common_flags` (operands land in `ARGS[]`).
- Validation: `require_file`, `require_dir`.
- Layout: `ensure_layout`, `write_durations_tsv`.
