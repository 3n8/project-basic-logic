# project-basic-logic

**The last step of the video pipeline: it turns approved pieces into one finished, repeatable `master.mp4`.**

You hand it a voice track, a timing list, one picture per shot, and optionally music and
captions. It hands back a finished video file. There is no AI in here and it makes no
creative decisions — it is deliberately boring, because boring is what makes it repeatable.
Run it twice on the same inputs and you get the same file, byte for byte.

---

## Contents

1. [What this actually is](#1-what-this-actually-is)
2. [The whole stack, from script to finished video](#2-the-whole-stack-from-script-to-finished-video)
3. [Where this repo sits](#3-where-this-repo-sits)
4. [The one idea you need to understand the video](#4-the-one-idea-you-need-to-understand-the-video)
5. [How the timing is worked out](#5-how-the-timing-is-worked-out)
6. [A real run, stage by stage](#6-a-real-run-stage-by-stage)
7. [What goes in, what comes out](#7-what-goes-in-what-comes-out)
8. [Running it](#8-running-it)
9. [The determinism guarantee](#9-the-determinism-guarantee)
10. [The two checks](#10-the-two-checks)
11. [Repo map](#11-repo-map)
12. [Glossary](#12-glossary)
13. [Troubleshooting / FAQ](#13-troubleshooting--faq)
14. [What this repo refuses to do](#14-what-this-repo-refuses-to-do)
15. [Related repos](#15-related-repos)

---

## 1. What this actually is

A video is three things glued together:

- **A voice** — someone talking for about four minutes.
- **Pictures** — in our case, one illustration per "shot" (slide).
- **Timing** — knowing exactly which picture is on screen while which words are spoken.

The hard part is never the glue. The hard part is that **the timing has to come from
somewhere trustworthy**, and the assembly has to be **repeatable** so you can rebuild a
video after fixing one picture without wondering whether the encoder quietly changed
something else.

This repo is only the glue. It:

1. Reads a **timing list** that says, in effect, "words 1–12 happen from 0.0 s to 3.6 s,
   words 13–30 from 3.6 s to 8.96 s, …".
2. Uses those timings to decide **how long each picture stays on screen**.
3. Turns each picture into a short silent clip of exactly that length.
4. Glues all those clips into one continuous video.
5. Mixes the voice (and optional music) into one audio track, at a correct, standard volume.
6. Burns the captions on and joins video + audio into the final `master.mp4`.

That's it. Everything else in this README is detail about those six steps.

---

## 2. The whole stack, from script to finished video

The finished video you watch is the output of **five different stages**, and only the
last one lives in this repo. This is the mental model to hold on to:

| # | Stage | What it does | Runs on | Produces |
|---|-------|--------------|---------|----------|
| 1 | **Script** | The words that get spoken (written by a human or an LLM) | anywhere | plain text |
| 2 | **Text-to-speech** (`qwen3-tts`) | Turns the script into an audio file of someone reading it | **Hel** (needs the GPU) | `narration.mp3` |
| 3 | **Forced alignment** (`qwen3-aligner`) | Listens to the audio + reads the script and reports the **start and end time of every single word** | **Hel** (needs the GPU) | `align-words.json` |
| 4 | **Cue grouping** (`group-cues.sh`) | Groups those individual words into **shots** — the chunks of time each picture covers | here, or upstream | `align-segment.json` |
| 5 | **Art** (ComfyUI) | Draws **one PNG per shot** in the house style | **Hel** (needs the GPU) | `frames/shot_0001.png`, … |
| 6 | **This repo** | Assembles everything into the final video | any machine with ffmpeg | `master.mp4` |

Read the table again with this in mind: **stages 2, 3 and 5 need a graphics card and are
slow; stage 6 needs neither.** That's the whole reason this repo exists as a separate
thing. The expensive, creative, GPU-bound work happens elsewhere; the cheap, mechanical,
must-be-identical-every-time work happens here.

```
   ┌──────────────────────── on Hel (the GPU machine) ─────────────────────────┐
   │                                                                           │
   │   script.txt ──▶ qwen3-tts ──▶ narration.mp3                              │
   │                      │                                                    │
   │                      ▼                                                    │
   │                qwen3-aligner ──▶ align-words.json  (every word's time)     │
   │                      │                                                    │
   │                      ▼                                                    │
   │                 group-cues ──▶ align-segment.json  (every SHOT's time)     │
   │                      │                                                    │
   │                      ▼                                                    │
   │              ComfyUI ──▶ frames/shot_0001.png … shot_0040.png (one per shot)│
   │                                                                           │
   └───────────────────────────────────┬───────────────────────────────────────┘
                                       │  four files, copied across
                                       ▼
   ┌────────────────── this repo: project-basic-logic ─────────────────────────┐
   │                                                                          │
   │   render-master.sh                                                       │
   │        │                                                                 │
   │        ├─ render-shot.sh          each PNG → a clip of the right length   │
   │        ├─ stitch-shots.sh         all clips → one video track             │
   │        ├─ mix-audio.sh            voice (+ music) → one audio track       │
   │        ├─ normalize-loudness.sh   audio → standard loudness               │
   │        ├─ burn-captions.sh        captions drawn onto the video           │
   │        └─ final mux               video + audio → master.mp4              │
   │                                                                          │
   └──────────────────────────────────┬───────────────────────────────────────┘
                                      ▼
                                 master.mp4
```

---

## 3. Where this repo sits

This repo owns **exactly one job**: given approved inputs, produce one reproducible
`master.mp4`.

Everything upstream is "approved inputs". That word matters. By the time files arrive
here, somebody (you) has decided what the script says, what each shot covers, and what
each picture looks like. This repo does not decide any of that, and it has no way to
change it.

Why separate it out at all, instead of just editing in a video editor?

- **It's repeatable.** An editor session is a one-off. This is a command.
- **It's inspectable.** Every decision is a short shell script you can read.
- **It's fixable.** If shot 17's picture is wrong, you replace one PNG and re-run. The
  other 39 shots come out identical, because the process is the same every time.
- **It's provable.** "Nothing else changed" is not a feeling here — it's a SHA-256 hash
  you can compare (see [§9](#9-the-determinism-guarantee)).

---

## 4. The one idea you need to understand the video

**The video is not animated. It is a slideshow with a voice track on top.**

Each shot is a single still picture. It sits on screen, completely motionless, for exactly
as long as it should. Then the next picture appears. There is no camera movement, no
fade, no zoom — nothing moves except the pictures changing and the captions appearing.

This is a deliberate style choice (it's the "hand-drawn explainer" look), and it's also
what makes the process fully automatic: "hold this PNG for 8.32 seconds" is a thing ffmpeg
can do exactly, deterministically, forever. Generative video is neither exact nor
repeatable.

So the whole video is:

```
picture 1 ......... 3.60 s
picture 2 ......... 5.36 s
picture 3 ......... 8.32 s
   ...
picture 40 ........ 7.20 s
                      ─────
                     228.320 s   ← total
```

and the voice track is 228.320 s long. They line up because both numbers come from the
same place — see next section.

---

## 5. How the timing is worked out

This is the part worth reading slowly, because it's the heart of the whole pipeline.

### Step A — every word gets a time

The aligner (stage 3) produces a list like this:

```json
{"text": "We've", "start": 0.24, "end": 0.40},
{"text": "all",   "start": 0.40, "end": 0.56},
{"text": "seen",  "start": 0.56, "end": 0.80}
```

That is *word-level* timing. A four-minute video has around 700 of these entries.

### Step B — words are grouped into shots

You can't draw 700 pictures, and you wouldn't want to — a picture per word would strobe.
So consecutive words are packed into **shots**: a run of words that belong together
logically, ending at a natural break (a full stop, a pause, a long sentence).

That packing is done by `bin/group-cues.sh`. It applies a fixed, readable rule set — for
example: prefer to cut after a sentence ending once the shot is at least 2 s old; split
long sentences on commas after about 3 s; never let one shot exceed 8.5 s. Nothing here
is a judgement call; it is a documented rule engine, so the same words always produce the
same shots.

The result is a much shorter list of **shot-level** timings:

```json
{"id": "shot_0001", "text": "We've all seen the clips …", "start": 0.0, "end": 3.6},
{"id": "shot_0002", "text": "the Ganges River …",          "start": 3.6, "end": 8.96},
{"id": "shot_0003", "text": "…",                           "start": 8.96, "end": 17.28}
```

This file is called `align-segment.json`, and **it is the most important input this repo
receives.** Each entry is one shot and therefore one picture.

### Step C — durations become a table

`group-cues.sh` deliberately snaps the first shot to start at `0.0` and the last shot to
end exactly at the audio length. So if you add up every shot's `end − start`, you get the
narration length back, to the millisecond. From the real run in this repo:

```
narration.mp3 ....................... 228.320042 s
sum of the 40 shot durations ........ 228.320 s
```

Those are the same number. That is not a coincidence — it's the invariant that makes the
picture track and the voice track the same length, which is what stops the video from
drifting out of sync.

This repo turns that list into a plain two-column table, `durations.tsv`:

```
shot_0001	3.6
shot_0002	5.360000000000001
shot_0003	8.32
```

`shot_NNNN` + `seconds`. Everything downstream reads this table.

### Step D — each picture is held for its duration

`render-shot.sh` takes `frames/shot_0001.png` and the number `3.6`, and produces a
3.6-second silent clip. Repeat 40 times. Concatenate. You now have the video track.

> **The critical naming rule.** Picture files must be named `shot_0001.png`,
> `shot_0002.png`, … and must line up *in order* with the entries in
> `align-segment.json`. Entry 1's picture is `shot_0001.png`, entry 2's is
> `shot_0002.png`, and so on. Nothing checks that a picture is *about the right thing* —
> it can't, the file is just a picture. If the order is wrong, you get perfectly-timed
> video with the wrong images under the words. This is the single most common way to get
> a subtly broken video.

---

## 6. A real run, stage by stage

This is the actual 228 s video this repo produced, with real numbers.

**The inputs**

- `narration.mp3` — 228.32 s of speech (7 chunks stitched, 683 words)
- `align-segment.json` — 40 shots
- `frames/` — 40 PNGs at 1920×1080
- `music.ogg` — a quiet bed
- `captions.srt` — 74 caption lines

**What `render-master.sh` does, in order**

**1/6 — Build the timing table.**
Reads `align-segment.json`, writes `durations.tsv`. Reports `40 shots`.
*Why:* every later step wants a simple `name → seconds` list, not nested JSON.

**2/6 — Render each shot.**
For each of the 40 rows: `shot_0001.png` + `3.6` → `shot_0001.mp4`.
Each clip is 1920×1080, H.264, 24 frames per second, silent.
*Why per-shot:* if one picture changes, only that one clip is rebuilt.

**3/6 — Stitch.**
Concatenates the 40 clips into `video.mp4` using ffmpeg's concat demuxer with
`-c:v copy`.
*Why `copy`:* it glues the clips without re-encoding, so nothing is degraded and the
result is stable.

**4/6 — Mix the audio.**
Voice at full level; music at 0.18× (about −15 dB) so it sits *under* the narration
instead of competing with it. Output: 48 kHz, stereo, 24-bit `audio_raw.wav`.
*Why stereo/48k:* that's what video platforms expect.

**5/6 — Normalise the loudness.**
Two passes of EBU R128 `loudnorm`:
pass 1 *measures* the file, pass 2 *applies* corrections using those measurements.
Target: **−16 LUFS** integrated, true peak **−1.5 dBTP**, loudness range 11.
Result on the real run: −16.37 LUFS, −1.49 dBTP.
*Why:* it makes your video as loud as everyone else's on YouTube/Spotify, so viewers
don't reach for the volume knob. −16 LUFS is the common streaming target.

**6/6 — Mux the master.**
Handles the captions according to the chosen mode (see below), then joins that video with
`audio.wav` into `master.mp4` (video copied, audio re-encoded as AAC 192 kbit/s,
`+faststart` so it starts playing before it's fully downloaded).

**Result**

| Measurement | Value |
|---|---|
| Length | 228.417 s |
| Narration length | 228.320 s |
| Difference | **0.097 s** (see below) |
| Picture | 1920×1080, 24 fps, H.264 |
| Audio | AAC, −16.37 LUFS, −1.49 dBTP |
| Shots | 40 |
| Captions | 74 |

The 0.097 s difference is **frame rounding**, and it's expected. Video frames land on
fixed 1/24-second boundaries, so a 3.6 s shot is 86 frames (3.583 s) or 87 (3.625 s) —
each shot can be off by up to half a frame, and 40 of those add up to a few hundredths of
a second over four minutes. Nobody can see or hear it, and it is *the same* every run,
because the rounding is deterministic too.

### Captions: three modes

Burn-in is no longer forced. Pick the mode per render with `--captions <mode>` (or the
`CAPTIONS` environment variable; the command line wins):

| Mode | What you get | Good for |
|---|---|---|
| `burn` *(default)* | Captions drawn permanently into the picture — always visible, in every player, with no toggles | **Shorts** and social clips, where they're part of the look and viewers usually watch muted |
| `soft` | A separate subtitle track sitting next to the audio, switchable on and off by the viewer | **Long-form** video, where baked-in text over four minutes is intrusive and can't be turned off or translated |
| `off` | No subtitles in the master at all | Clean masters, or when you want to add subtitles later in an editor |

```sh
bin/render-master.sh --captions soft ep001 outputs/ep001/master.mp4
make render NAME=ep001 CAPTIONS=off
```

The mode is ignored when there is no `inputs/captions.srt`, and an invalid mode stops the
run with a clear message rather than silently guessing. `burn` is the default, so an
existing call behaves exactly as before — verified by re-rendering the full 228 s cut and
comparing hashes (identical, `d18e4b45…`).

---

## 7. What goes in, what comes out

### Inputs

`inputs/` is **gitignored** — media never gets committed. Convention for a named run:
put everything in `inputs/<name>/`.

| File | Required | What it is |
|---|---|---|
| `align-segment.json` | **yes** | One entry per shot, with `start`/`end` in seconds |
| `frames/shot_NNNN.png` | **yes** | One picture per shot, 4-digit, 1-based, in order |
| `narration.mp3` | **yes** | The voice track |
| `music.ogg` | no | Background bed; skipped if absent |
| `captions.srt` | no | Subtitles; burned in if present |

### Outputs

Everything lands in `outputs/<name>/`:

| File | What it is | Kept? |
|---|---|---|
| `durations.tsv` | `shot_NNNN<TAB>seconds` table | yes |
| `concat.txt` | the list of clips for the stitcher | yes |
| `shot_NNNN.mp4` | one silent clip per shot | yes |
| `video.mp4` | all shots stitched | yes |
| `audio_raw.wav` | mixed, not yet normalised | deleted after use |
| `audio.wav` | mixed **and** normalised | yes |
| `captions.srt` | a copy of the input captions (only when captions are used) | yes |
| `captioned.mp4` | video with captions burned in or added as a soft track | deleted after use |
| **`master.mp4`** | **the finished video** | yes |

`master.mp4` is the only file you actually want. The rest are kept so you can inspect any
stage and see exactly where a problem came from.

---

## 8. Running it

### Quick start

```sh
bin/render-master.sh <name> <where-to-write-master.mp4> [inputs_dir] [outputs_dir]

# e.g. a run called "ep001":
bin/render-master.sh ep001 outputs/ep001/master.mp4
```

### The friendly way

```sh
make render NAME=ep001     # do the run
make dry-run NAME=ep001    # print the whole plan, touch nothing
make check                 # run the project's own checks
make smoke                 # 3-shot end-to-end self test, all three caption modes
make clean NAME=ep001      # delete outputs/ep001/
make render NAME=ep001 CAPTIONS=soft   # caption modes: burn (default) | soft | off
make help
```

### Always plan before you commit

A real run is minutes of ffmpeg. `--dry-run` prints **every command that would run** and
writes no media at all, so you can check the plan first:

```sh
make dry-run NAME=ep001
# or
bin/render-master.sh --dry-run ep001 outputs/ep001/master.mp4
```

Every script in `bin/` supports `--dry-run` (or the environment variable `DRY_RUN=1`).
Dry-run does write its two small text intermediates (`durations.tsv`, `concat.txt`) —
it skips media, not bookkeeping — and its last log line says exactly that.

### Prerequisites

| Tool | Why |
|---|---|
| `bash` 5+ | every script uses `set -euo pipefail` and arrays |
| `ffmpeg` + `ffprobe` | does all the actual work |
| `jq` | reads JSON (timings) from the shell |
| `awk` (gawk) | used by the caption and cue packers |
| `shellcheck` | optional; used by `scripts/check` |

No Python. No Node. No GPU.

---

## 9. The determinism guarantee

**Same inputs in → same bytes out.** That's the whole promise, and it's the reason the
repo is allowed to be boring.

Why it matters: it means the output is a *function of the inputs*. If the finished video
changes, an input changed. You never have to wonder whether the encoding drifted, whether
the tool version shifted a pixel, or whether last week's run was subtly different.

**How it's proven, not just claimed.** On 2026-09-18 the pipeline was refactored (every
script gained a dry-run mode, several bugs were fixed) and then the same 228 s video was
re-rendered from the same inputs:

```
sha256  d18e4b45d58261dacf33ecf4dc7cace74e0b00175835fd481add13501eddf57f  before
sha256  d18e4b45d58261dacf33ecf4dc7cace74e0b00175835fd481add13501eddf57f  after
```

Identical — the refactor provably changed nothing about the output.

**What would break it** (i.e. what counts as a new video, not a bug):

- a different `narration.mp3` (re-synthesised speech)
- a different `align-segment.json` (different shot boundaries)
- any re-rendered PNG
- a different ffmpeg encoder version

If any of those change, re-run and expect a different file. That's correct behaviour:
different inputs are different inputs.

---

## 10. The two checks

**`scripts/check`** — the static check. Lints every shell script with `shellcheck`
(at warning level and above, where it must be clean) and validates any `inputs/*.json`
against `schemas/align-segment.schema.json`. It even finds `shellcheck` in `~/.local/bin`
if your PATH doesn't have it, rather than quietly skipping — a check that silently does
nothing is worse than no check.

**`scripts/smoke`** — the "does the whole thing actually run" check. It generates a tiny
3-shot / 6-second fixture (three colour frames and a quiet tone, built by
`bin/make-smoke-fixture.sh` — nothing committed, since `inputs/` is gitignored) and runs
the entire pipeline over it, failing if it takes more than 90 seconds. It takes about
**1 second**. It uses a faster encoder setting on purpose: the point is to prove the
plumbing, not to produce a pretty test video.

Run both before you trust a change. `make check` and `make smoke`.

---

## 11. Repo map

```
bin/                        the scripts (each does exactly one thing)
  render-master.sh          the orchestrator — run this one
  render-shot.sh            one PNG + a duration → one silent clip
  stitch-shots.sh           40 clips → one video track
  mix-audio.sh              voice (+ music) → one audio track
  normalize-loudness.sh     EBU R128 loudness normalisation, two passes
  burn-captions.sh          draw captions on, or add them as a soft track (--soft)
  extract-segment-duration.sh   timings JSON → durations.tsv
  make-srt.sh               word timings → caption file (SRT)
  group-cues.sh             word timings → shot timings        (dev utility)
  make-placeholder-frames.sh    shot timings → labelled dummy PNGs (dev utility)
  make-smoke-fixture.sh     builds the tiny self-test fixture

lib/common.sh               shared helpers: logging, constants, dry-run, layout,
                            and the durations.tsv writer. Source it, never run it.

schemas/                    JSON Schema for the timings file

docs/PIPELINE.md            the stage-by-stage pipeline view
docs/SCRIPTS.md             per-script contract: arguments, inputs, outputs, exit codes

scripts/check               lint + schema validation
scripts/smoke               end-to-end self test

inputs/                     media goes here (gitignored; only README.md is tracked)
outputs/                    finished runs go here (gitignored)

Makefile                    friendly wrappers over bin/
GOAL.md                     what this repo is for, and what it refuses to become
TODOLIST.md                 done / outstanding work
CHANGELOG.md                what changed, when
AGENTS.md                   working agreement for AI agents editing this repo
LICENSE                     MIT
```

**Dev utilities vs pipeline stages.** `group-cues.sh` and `make-placeholder-frames.sh`
are *not* called by `render-master.sh`. They exist so you can build a full-length cut —
and look at it — before the real artwork exists. Real shot boundaries are approved
upstream, before ComfyUI draws anything.

---

## 12. Glossary

| Term | Plain meaning |
|---|---|
| **TTS** | Text-to-speech. Software that reads the script aloud and saves it as audio. |
| **Forced alignment** | Software that takes audio *plus* its transcript and reports the exact start/end time of every word. |
| **Word-level timing** | A timestamp for each individual word. ~700 entries per four-minute video. |
| **Cue / shot** | A run of words that share one picture. This is what you can actually see. |
| **Shot-level timing** | A timestamp per shot instead of per word. 40 entries in our example. |
| **Frame** | One still image in the video. At 24 fps, one second of video is 24 frames. |
| **fps** | Frames per second. This pipeline is fixed at 24 and never deviates. |
| **Freeze frame** | Holding one picture for many frames, so it looks like a single image that stays on screen. Our whole video is this. |
| **Clip** | Here: one silent video segment made from one picture, of one shot's length. |
| **Concat** | Joining video files end to end. |
| **Mux** | Putting a video track and an audio track into one file. That's what "muxing" means. |
| **Burn-in captions** | Captions drawn permanently onto the picture, so they're visible everywhere, always. The alternative ("soft") keeps them as a separate switchable track. |
| **Loudness / LUFS** | A standardised measurement of perceived volume. −16 LUFS is the usual streaming target. |
| **True peak (dBTP)** | The loudest instant in the audio, including peaks between samples. Kept below −1 dB to stop distortion on playback. |
| **EBU R128** | The broadcast standard describing those loudness rules. |
| **CRF** | The quality dial for H.264: lower is better and bigger. Fixed at 20 here. |
| **Faststart** | Writing the file so playback can begin before the whole file has downloaded. |
| **Deterministic** | Same input, same output, every time — not "usually", strictly. |
| **Dry run** | Show the plan; change nothing. |

---

## 13. Troubleshooting / FAQ

**The video plays but the pictures don't match the words.**
The most likely cause: the frame files are in the wrong order, or mis-numbered, relative
to `align-segment.json`. Entry 7 needs `shot_0007.png` — not `shot_0006.png`, and not a
file that was skipped. Check for gaps in the numbering too.

**`missing frame: inputs/.../shot_0017.png`**
`align-segment.json` has 17+ shots but you supplied fewer pictures. Every shot needs
exactly one.

**The video is slightly longer than the narration (by a fraction of a second).**
Expected. Frames land on 1/24-second boundaries, so each shot rounds to the nearest frame
(§6). It's the same every run.

**"It ran but `master.mp4` doesn't exist."**
This used to be possible via a swallowed error; it's fixed. Now a failed step stops the
run and the last line of output is the reason. Read the tail of the output.

**My audio is silent and the loudness step complained.**
Digital silence measures as `-inf`, which cannot be corrected. The script detects that and
falls back to a single-pass normalisation instead of failing. If you see it, your input
audio is (near) silent — that's almost always a bug upstream, not here.

**It's slow.**
Almost all the time is the encoder running twice over the picture (once per shot, once
when burning captions) at `-preset slow`. That's a deliberate quality choice. Use
`--dry-run` to plan, and change the preset via the `X264_PRESET` environment variable if
you need speed over quality.

**Can I use this on a Mac?**
Yes — it's just bash and ffmpeg. `brew install ffmpeg jq gawk shellcheck bash`.

**Do I need the GPU for this?**
No. The GPU is for the stages *before* this one (speech, alignment, artwork).

---

## 14. What this repo refuses to do

Stated plainly, because boundaries are what keep this thing reliable:

- **No creative decisions.** It never chooses a shot boundary, invents a picture, picks a
  font, or re-times anything to taste. Shot boundaries are decided upstream and approved
  before art is drawn; captions are generated by a fixed rule; fonts and colours are
  constants in the scripts.
- **No generative model.** Nothing here calls an AI. Art and speech are made elsewhere and
  arrive as plain files.
- **No Python.** Every script is bash + ffmpeg + jq + awk. (The early Python helpers were
  rewritten as shell scripts, proven byte-identical to the originals.)
- **No half-done runs.** If a step fails, the run stops. It does not "finish" anyway and
  leave you with a file that looks right but isn't.

If a proposed change would make the output depend on anything other than the input files,
it doesn't belong in this repo.

---

## 15. Related repos

- `qwen3-tts` — turns the script into speech (GPU, on Hel)
- `qwen3-aligner` — reports the timing of every word (GPU, on Hel)
- ComfyUI — draws the pictures (GPU, on Hel)

Published here: <https://gitea.nettsi.de/en/project-basic-logic>

## License

MIT — see [LICENSE](LICENSE).
