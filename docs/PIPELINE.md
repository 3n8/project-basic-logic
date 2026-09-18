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

   `--format 9:16` changes the geometry of every clip in the run: 1080x1920 instead of the
   source size, so video.mp4 and master.mp4 come out vertical too. The stage order is
   identical either way.
```

## Stages

1. **render-shot** — one PNG + one duration → one MP4 freeze-frame clip.
   Done per-shot, in parallel if you want. Per-shot durations come from
   `align-segment.json` via `jq`.

   The clip's geometry is the run's `--format`. `16:9` (default) encodes the still as
   supplied. `9:16` fits the still into `SHORTS_W`×`SHORTS_H` (1080×1920): a blurred,
   centre-cropped copy fills the frame and the whole still is scaled to fit and centred on
   top of it — the picture is never cropped. Fixed filter graph, fixed constants, so the
   same still always produces the same clip.

2. **stitch-shots** — concat all per-shot MP4s into a single video using
   ffmpeg's `-c:v copy` (lossless) concat demuxer. No re-encode at this
   stage; that's deliberate so the stitched file is byte-stable.

3. **mix-audio** — `amix` filter, narration at full level + music at
   0.18× linear (≈ −15 dB). Output is 48 kHz / 2ch / PCM-24 wav.

4. **normalize-loudness** — EBU R128 two-pass (`loudnorm` with
   `linear=true`). Target I=-16, TP=-1.5, LRA=11. Pass 1 measures,
   pass 2 applies. Output is again 48/2/PCM24.

5. **burn-captions** — if `captions.srt` exists, mux into video according to the
   caption mode chosen on the orchestrator (`--captions burn|soft|off`):
   `burn` draws the text into the picture (image-rendered, always visible), `soft`
   attaches a switchable subtitle track, `off` skips captions entirely. The final
   mux maps the subtitle stream only when one exists.

   The burn-in style follows the run's format: `CAPTION_STYLE_WIDE` (the original
   `FontSize=22`) for 16:9, `CAPTION_STYLE_TALL` (`FontSize=14`, `MarginV=42`,
   `MarginL/R=25`) for 9:16. libass scales the style font by frame height, so the tall
   style draws a larger line than the wide one (78 px vs 69 px measured) while keeping the
   block in the bottom safe area. `soft` is unaffected: the player styles that track.

6. **render-master** (orchestrator) — runs 1–5 in order, plus the final
   mux: video + audio + optional captions.

## Formats

`--format 16:9|9:16` (default `16:9`) is decided once by the orchestrator and passed to
`render-shot.sh` and `burn-captions.sh`; nothing downstream branches on it. The two formats
produce the same stage sequence, the same timings and the same audio — only the frame
changes.

The vertical target (`SHORTS_W`×`SHORTS_H`, default 1080×1920) is reached by fitting, not
cropping, so no approved artwork is ever cut off:

```
fill   : scale(cover 1080x1920) → crop(1080x1920) → gblur(sigma=SHORTS_BLUR)
picture: scale(fit 1080x1920)                    → overlay(centred)
```

Because captions are burned *after* this, on the finished vertical frame, no later stage can
crop text away.

**Length cap.** A `9:16` run longer than `SHORTS_MAX_SECONDS` (default 60) aborts after the
durations table and before writing media. The checked length is the sum of the shot
durations — the same closed timeline the video is built from. Nothing truncates the audio.

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
identical input audio. The 9:16 fit is a fixed filter graph with fixed constants
(`SHORTS_W`, `SHORTS_H`, `SHORTS_BLUR`), so a vertical run is equally repeatable.

The `16:9` default is a separate branch from the vertical fit and its caption style is the
byte-identical string it always was, so adding `--format` could not change an existing
master — re-rendering the 228 s cut reproduced its recorded SHA-256, and a second render of
the same vertical inputs reproduces the first file byte for byte.

## Outside the master path

- `bin/group-cues.sh` — deterministic rule engine that packs a word-level
  aligner JSON into shot cues. Not invoked by `render-master.sh`; used to
  build a cuttable length from an aligner JSON alone.
- `bin/make-placeholder-frames.sh` — deterministic 1920x1080 PNG per cue
  for running the pipeline before approved frames exist. Not invoked by
  `render-master.sh`.
