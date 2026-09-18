# Changelog

## Unreleased

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
