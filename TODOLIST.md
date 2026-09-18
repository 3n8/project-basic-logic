# TODO

## Open

_None — all items below are done._

## Done

- [x] Add `--dry-run` flag to every `bin/` script — print the planned ffmpeg command, do not invoke.
      Implemented once in `lib/common.sh` (`parse_common_flags`, `run`, `make_dir`, `wrote`);
      every ffmpeg call in `bin/` goes through `run`. `--dry-run` and `DRY_RUN=1` both work.
- [x] Add `bin/extract-segment-duration.sh` — read aligner JSON via jq and emit `inputs/durations.tsv` for the orchestrator.
- [x] Document the `HSA_OVERRIDE_GFX_VERSION` invariant for AMD users (irrelevant here since we don't touch the GPU).
      See README.md § "AMD / ROCm hosts".
- [x] Add `bin/make-srt.sh` — generate SRT captions from aligner JSON (sub-second precision, words coalesced into ~2 second captions).
      bash + jq + awk; byte-identical to the former `bin/make-srt.py` (verified, 74 cues / 6512 bytes), which it replaces.
- [x] Add a `Makefile` or `justfile` wrapper for callers who don't want to type `bin/render-master.sh` directly.
      `Makefile` with `render`, `dry-run`, `check`, `smoke`, `clean`, `help`.
- [x] Add a tiny smoke test: `inputs/smoke/align-segment.json` + `inputs/smoke/frames/shot_NNNN.png` + `inputs/smoke/narration.mp3` that runs end-to-end on an empty Hel home in <90 s.
      `bin/make-smoke-fixture.sh` generates the fixture (inputs/ is gitignored); `scripts/smoke` runs it. Measured 1 s.
- [x] 0.1.0 scaffold.
- [x] copy auth.json + gh + tea configs from Hel so opencode does not need forced --model
