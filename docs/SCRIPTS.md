# Scripts

Every script is a single, runnable shell file under `bin/`. They share
helpers via `lib/common.sh`. Run them in pipeline order; see [PIPELINE.md](PIPELINE.md).

Every `bin/*.sh` script accepts `--dry-run` (or `DRY_RUN=1`): it prints the exact
ffmpeg command it would run and writes no media. In dry-run the downstream
`require_file` checks are relaxed, because intermediate files were never written.

## `bin/render-shot.sh`

Render one freeze-frame MP4 from one PNG.

```
bin/render-shot.sh [--dry-run] [--format 16:9|9:16] <input.png> <duration_seconds> <output.mp4>
```

| Arg | Required | Notes |
|-----|----------|-------|
| `input.png` | yes | Frame from ComfyUI |
| `duration_seconds` | yes | > 0; from `align-segment.json` |
| `output.mp4` | yes | Will be overwritten (`-y`) |

| Flag | Default | Notes |
|------|---------|-------|
| `--format 16:9\|9:16` | `16:9` | Output geometry. Also settable via the `FORMAT` env var; the flag wins. An invalid value aborts. |

With `16:9` the still is encoded as supplied (no scaling, the existing behaviour). With
`9:16` the clip is the vertical target `SHORTS_W`×`SHORTS_H` (1080×1920): a blurred,
centre-cropped copy of the still fills the frame and the **whole** still is fitted on top of
it, centred. The picture is never cropped. The fit is fixed and deterministic —
`scale`(cover) + `crop` + `gblur=sigma=$SHORTS_BLUR` for the fill, `scale`(fit) + `overlay`
for the picture — and `SHORTS_W`/`SHORTS_H` must be positive even numbers (aborts otherwise).

Because the geometry is applied per shot, all clips in a run share it and `stitch-shots.sh`
still concatenates with `-c:v copy`.

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
`render-master.sh`, which picks the mode and the format; run it directly only to redo this
step alone.

```
bin/burn-captions.sh [--dry-run] [--format 16:9|9:16] <input.mp4> <captions.srt> <output.mp4> [--soft]
```

`--format` selects the burn-in style; `--soft` ignores it, because the player styles a
subtitle track. libass scales the style font by the frame **height**, so the same `FontSize`
draws much larger text on a 9:16 frame. Both looks are constants (env-overridable):

| Constant | Format | Value |
|----------|--------|-------|
| `CAPTION_STYLE_WIDE` | 16:9 (default) | `FontSize=22`, no margins — unchanged from before this option existed |
| `CAPTION_STYLE_TALL` | 9:16 | `FontSize=14`, `MarginV=42`, `MarginL=25`, `MarginR=25` |

Measured on the reference captions: a 69 px ink line on a 1920-wide frame for the wide
style, and 78 px on a 1080-wide frame for the tall style — bigger in pixels and about twice
as big relative to frame width. The tall margins put the block in the bottom safe area; the
worst reference caption (75 characters) wraps to four lines, 359 px tall, ending 281 px
above the bottom edge and clear of the picture band.

## `bin/render-master.sh`

The orchestrator. Runs every stage in order.

```
bin/render-master.sh [--dry-run] [--captions burn|soft|off] [--format 16:9|9:16] <name> <master.mp4> [inputs_dir] [outputs_dir]
```

| Flag | Default | Notes |
|------|---------|-------|
| `--dry-run` | off | Print every planned ffmpeg command, write no media (also `DRY_RUN=1`) |
| `--captions burn\|soft\|off` | `burn` | How to handle `captions.srt`. Also settable via the `CAPTIONS` env var; the flag wins. An invalid value aborts. Mode is ignored when there is no `captions.srt`. |
| `--format 16:9\|9:16` | `16:9` | Output geometry. Also settable via the `FORMAT` env var; the flag wins. An invalid value aborts. |

Caption modes: **`burn`** draws the text into the picture (always visible, the Shorts
look); **`soft`** attaches a switchable subtitle track next to the audio (long-form);
**`off`** leaves the master without subtitles.

Formats: **`16:9`** is the existing landscape master and is byte-for-byte unaffected by this
option. **`9:16`** is a vertical Shorts/Reels/TikTok master at `SHORTS_W`×`SHORTS_H`
(1080×1920), captioned with `CAPTION_STYLE_TALL`; the stills are fitted, never cropped (see
`render-shot.sh` above).

**Short-form length cap.** A `9:16` run whose timeline exceeds `SHORTS_MAX_SECONDS`
(default 60) aborts after the durations table, before any media is written:

```
[FATAL] 9:16 is capped at 60s but this input is 228.320s — refusing to truncate the audio;
supply a short cut, or raise SHORTS_MAX_SECONDS deliberately
```

The length checked is the sum of `durations.tsv`, i.e. the closed timeline the video is
built from. The audio is never truncated; there is no "fit it to the cap" mode. Raise the
table deliberately (`SHORTS_MAX_SECONDS=180 …`) if you want a longer vertical cut.

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

Covered: all three caption modes; both formats; the encoded geometry read back with
`ffprobe` (320×180 for the default 16:9 pass-through of the fixture, `SHORTS_W,SHORTS_H` for
`--format 9:16`); the subtitle-track shape (burn/off → none, soft → one); and both refusal
paths — an unknown `--format` value, and a `9:16` run over a deliberately tiny
`SHORTS_MAX_SECONDS`, which must abort **and leave no master behind**.

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

- Constants: `FPS`, `X264_PRESET`, `X264_CRF`, `X264_TUNE`, `LOUDNORM_*`, `AUDIO_CODEC`, `AUDIO_BITRATE`,
  `FORMAT`, `SHORTS_W`, `SHORTS_H`, `SHORTS_BLUR`, `SHORTS_MAX_SECONDS`.
- Logging: `log`, `stage`, `die`, `wrote`.
- Tool presence: `need`, `require_tools`.
- Dry run: `dry_run_enabled`, `run`, `make_dir`, `parse_common_flags` (operands land in `ARGS[]`).
- Format: `parse_format_flag` (consumes `--format`, operands land in `ARGS[]`), `validate_format`
  (aborts on anything but `16:9`/`9:16`).
- Validation: `require_file`, `require_dir`.
- Layout: `ensure_layout`, `write_durations_tsv`.
