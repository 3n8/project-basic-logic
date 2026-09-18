# Changelog

## Unreleased

- **Docs: README.md rewritten** as a full explanation of the stack for a non-expert
  reader: the five upstream stages and what each machine does, the timeline model
  (words → cues → shots → durations → frames), a real 228 s run stage by stage with
  measured numbers, the determinism guarantee and its SHA-256 proof, a repo map, a
  glossary, and troubleshooting.
- **Added AGENTS.md**: the working agreement for agents editing this repo — bash +
  ffmpeg + jq + awk only (no Python), no creative layer, `--dry-run` mandatory on new
  scripts, the frame-name/order invariant, and the byte-identity proof method required
  when replacing a component.
- Published to `gitea.nettsi.de/en/project-basic-logic` (private, matching `en/qwen3-tts`).
- Fixed `bin/mix-audio.sh`: the `amix` filter graph mixed `$music_vol[music]`,
  which shellcheck flags as SC1087 (array subscript) and which is fragile in
  bash. Braced as `${music_vol}[music]`. `shellcheck --severity=warning` is now
  clean across `bin/*.sh`, `lib/*.sh`, `scripts/check`, `githooks/pre-push`.
  `scripts/check`'s shellcheck step now actually runs on this host (shellcheck
  0.10.0 in `~/.local/bin`) instead of printing its skip WARN.
- `bin/render-master.sh` dry-run closing line now reads "no media written" instead
  of "nothing written": dry-run still writes the two text intermediates
  (`durations.tsv`, `concat.txt`) into the run directory, it only skips media.
- Verified `bin/extract-segment-duration.sh` byte-matches `outputs/full/durations.tsv`
  and `outputs/prefix/durations.tsv` when run on the shot-level `align-segment.json`
  inputs. On the word-level `inputs/reference/full_align_words.json` it emits one row
  per word (683), which is expected — that file has no shot boundaries.
- `bin/group-cues.sh`: bash + jq + awk cue packer, byte-identical to the
  removed `bin/group-cues.py` (verified on both reference alignments: 118-word
  prefix and 683-word full; cmp + sha256sum match, plus a 250-case randomized
  comparison and a hand-built edge fixture).
- `bin/make-placeholder-frames.sh`: bash port that emits byte-identical PNGs
  to the removed `bin/make-placeholder-frames.py` (verified on the full
  reference cue set: 40 PNGs; cmp + sha256sum match).
- Removed the last two Python helpers: `bin/group-cues.py` and
  `bin/make-placeholder-frames.py`. `bin/` is now bash + FFmpeg + jq + awk only.
- `bin/normalize-loudness.sh`: the loudnorm pass-1 measurement is extracted from
  ffmpeg's stderr with awk instead of an inline `python3 -c`. That was the last
  runtime Python dependency in the repo, so the "bash + FFmpeg only" claim in
  GOAL.md and README.md is now literally true.
- Fixed: `bin/group-cues.sh` treats a falsy top-level `duration` (`0`, `null`,
  absent) as missing, matching Python's `data.get("duration") or words[-1]["end"]`.
- Fixed (latent, unreachable): the `bin/group-cues.sh` forward-merge shift loop
  stopped one element short. The branch cannot be reached — every non-final pack
  flush requires a cue of at least 2.0 s — but the bound is now correct.
- GOAL.md, README.md, docs/PIPELINE.md: explicit "no creative layer" / dev-utilities
  boundary text; awk added to the prerequisites table.
- `bin/group-cues.sh` documented deviation: a segment whose `text` is JSON `null`
  is skipped (matches Python's `if not text: continue` after `.strip()` instead
  of `str(None)` keeping the literal word `None`); missing `text` keys are also
  skipped, matching Python.
- `--dry-run` (and `DRY_RUN=1`) on every `bin/` script: prints the exact planned
  ffmpeg command and writes no media. Implemented once in `lib/common.sh`
  (`parse_common_flags`, `run`, `make_dir`, `wrote`); all ffmpeg calls route through `run`.
- `bin/extract-segment-duration.sh`: aligner JSON → `inputs/durations.tsv` via `write_durations_tsv`.
- `bin/make-srt.sh`: bash + jq + awk SRT generator, byte-identical to the removed
  `bin/make-srt.py` (74 cues / 6512 bytes on the full reference input).
- `Makefile`: `render`, `dry-run`, `check`, `smoke`, `clean`, `help`.
- `bin/make-smoke-fixture.sh` + `scripts/smoke`: tiny end-to-end fixture and runner
  (3 shots, 6 s), budgeted at 90 s; measured 1 s.
- Fixed: `ensure_layout` died instead of creating a missing outputs root.
- Fixed: `render-master.sh` swallowed a failed final mux via `|| true`, then logged
  "ready" — the master could be missing with a success log.
- Fixed: `normalize-loudness.sh` aborted on silence (`-inf` measurements); it now
  falls back to single-pass loudnorm when the measured values are not finite.
- Fixed: latent `set -e` trap in `render-master.sh` when `music.ogg` was absent.
- Docs: README § Makefile / smoke / dry-run and § AMD / ROCm hosts (`HSA_OVERRIDE_GFX_VERSION`).
- Scaffold: `bin/{render-shot,stitch-shots,mix-audio,normalize-loudness,burn-captions,render-master}.sh`, `lib/common.sh`, `schemas/align-segment.schema.json`.
- `scripts/check` runs `shellcheck` on `bin/` and validates any `inputs/*.json` against the schema.
- `githooks/pre-push` invokes `scripts/check`.
- `opencode.json` enables the ponytail plugin (same as `envim`).
- Dual docs: `docs/PIPELINE.md`, `docs/SCRIPTS.md`.

## 0.1.0

- Project stand-up. No prior history.
