# AGENTS.md — working agreement for project-basic-logic

Read [README.md](README.md) first for what this repo is and how the pipeline works.
[GOAL.md](GOAL.md) is the one-sentence contract. This file is the rules for **changing**
the repo without breaking its promise.

## The promise

**Same inputs in → same bytes out.** Everything below exists to protect that.

If you cannot demonstrate that a change preserves determinism, it does not belong here.

## Hard rules

1. **bash + ffmpeg + jq + awk only. No Python, no Node, no guest languages.**
   There is no `python3` call anywhere in `bin/`, `lib/`, `scripts/` or `githooks/`.
   Do not add one. (Note: `grep -o` is line-oriented and will not extract a multi-line
   JSON object — that is why the loudness measurement is done with `awk`.)
2. **No creative layer.** No generative model, no per-frame judgement, no taste-based
   timing. A documented, fixed rule set is fine (that is plumbing); anything whose output
   depends on a model, a random seed, or a human's opinion is not.
3. **`FPS` stays 24.** It lives in `lib/common.sh`. Changing it changes every output.
4. **Never `git push` without explicit confirmation from the owner.**
5. **No half-done runs.** A failing step must stop the run with a non-zero exit. Never
   swallow an ffmpeg failure with `|| true` — that is exactly how a missing `master.mp4`
   once got logged as "ready".

## Script conventions

Every script in `bin/` follows the same shape:

```bash
#!/usr/bin/env bash
# one-line purpose
# Usage: bin/thing.sh [--dry-run] <args...>

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

[ "$#" -eq N ] || die "usage: thing.sh [--dry-run] <args...>"
```

- **`--dry-run` is mandatory for every new script.** Route every external command
  through the `run` helper from `lib/common.sh`; it prints `[dry-run] <command>` and
  returns 0 instead of executing. Accept `DRY_RUN=1` in the environment too.
- Use `make_dir` instead of `mkdir -p` so dry-run does not create directories.
- Use `wrote <label> <path>` for the closing log line instead of `log "... wrote ..."`,
  so dry-run says "would write" and never claims work it did not do.
- Log to **stderr** via `log` / `stage` / `die`. `die` exits 1.
- Relax `require_file` checks only for files this run would have produced — see
  `normalize-loudness.sh` and `burn-captions.sh` for the pattern.
- **User-facing choices are flags, documented, with a safe default.** The caption mode is
  the model: `--captions burn|soft|off` in `render-master.sh`, `CAPTIONS` in the Makefile,
  `burn` as the default so no existing call changes behaviour, and an abort on a bad value.
  Follow that shape when adding the next option. Do not silently change a default.
- Add a `# shellcheck source=lib/common.sh` comment above the `source` line.
- **Dry-run must write no media.** Text bookkeeping (`durations.tsv`, `concat.txt`) is
  allowed; `.mp4`/`.wav`/`.png` never.

## Invariants that are easy to break

- **Frame naming and order.** `frames/shot_NNNN.png`, 4-digit, 1-based, no gaps, and
  entry *N* of `align-segment.json` must be the picture for shot *N*. Nothing can verify
  that a picture matches its words — a wrong order produces a perfectly-timed video with
  the wrong images, which is the worst failure mode here because it looks fine.
- **Timeline closure.** The first shot starts at `0.0` and the last ends exactly at the
  narration length, so the shot durations sum to the audio duration. `group-cues.sh` is
  responsible for that snap. Do not add a stage that breaks it.
- **`durations.tsv` format** is `shot_NNNN<TAB>seconds`, written by
  `write_durations_tsv` in `lib/common.sh`. Other scripts parse it; do not hand-roll it.
- **Stitch and final mux copy the video stream** (`-c:v copy`). Do not introduce a
  re-encode there — it would break byte-stability for no benefit.

## Before you commit

```sh
scripts/check     # shellcheck (warning+ must be clean) + JSON schema validation
scripts/smoke     # 3-shot end-to-end run; must pass in under 90 s (~1 s expected)
```

- `scripts/check` finds `shellcheck` in `~/.local/bin` if it is not on `PATH`. If it
  reports the tool missing, confirm the tool is genuinely absent before believing it.
- If you add or change a script, update `docs/SCRIPTS.md` and add a `CHANGELOG.md` entry.
- If you close a task, update `TODOLIST.md`.

## Replacing or porting a component

When a component is rewritten, prove behaviour is unchanged rather than asserting it:

1. Recover the original, e.g. `git show <rev>:bin/old.py > /tmp/old.py`.
2. Run both on the **real reference inputs** and compare byte-for-byte (`cmp`, `sha256sum`).
3. Run a **randomised fuzz** comparison — reference inputs alone do not exercise the
   branches where a hand-translation typically diverges.
4. Build an **edge fixture**: missing/empty fields, reversed timings, equal start/end,
   quotes and backslashes in text, non-ASCII, missing optional fields.
5. Report any divergence you find, even if you fix it. Do not describe a behavioural
   difference as "equivalent".

## Working with the upstream stages

Speech, alignment and artwork happen on the GPU host (Hel) and are **not** this repo's
job. If a fix requires re-synthesising narration, re-aligning, or re-drawing pictures,
say so — that is an upstream change, and it means a new video, not a rebuild.

## Handy facts

- A full 228 s run: 40 shots, 40 clips, ~74 captions, 1920×1080, ~27 MB master.
- Constants (all in `lib/common.sh`): `X264_PRESET=slow`, `X264_CRF=20`,
  `X264_TUNE=stillimage`, `LOUDNORM_I=-16`, `LOUDNORM_TP=-1.5`, `LOUDNORM_LRA=11`,
  `AUDIO_CODEC=aac`, `AUDIO_BITRATE=192k`; music gain is `0.18` in `mix-audio.sh`.
- Determinism proof on file: re-rendering after the 2026-09-18 refactor produced
  `sha256 d18e4b45…` both times — see README §9.
