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
- [x] Add `bin/group-cues.sh` — pack word-level aligner JSON into semantic shot cues.
      bash + jq + awk; byte-identical to the former `bin/group-cues.py` on both reference alignments
      (118-word prefix and 683-word full, cmp + sha256sum match), which it replaces.
- [x] Add `bin/make-placeholder-frames.sh` — one uniquely coloured 1920x1080 PNG per cue.
      bash port; byte-identical PNGs to the former `bin/make-placeholder-frames.py` on the full reference cue set
      (40 PNGs, cmp + sha256sum match), which it replaces.
- [x] Delete the last two Python helpers (`bin/group-cues.py`, `bin/make-placeholder-frames.py`) — `bin/` is now bash + FFmpeg + jq + awk only.
- [x] Document the boundary in GOAL.md, README.md, docs/PIPELINE.md, docs/SCRIPTS.md:
      `group-cues.sh` and `make-placeholder-frames.sh` are deterministic dev utilities, not pipeline stages;
      `render-master.sh` never calls them.
- [x] Document the `group-cues.sh` text:null deviation (skip instead of keeping `str(None)`).
- [x] Remove the last runtime Python dependency: `bin/normalize-loudness.sh` extracted the loudnorm
      pass-1 measurement with an inline `python3 -c`; it now uses awk. `bin/` is bash + FFmpeg + jq + awk.
- [x] Add a `Makefile` or `justfile` wrapper for callers who don't want to type `bin/render-master.sh` directly.
      `Makefile` with `render`, `dry-run`, `check`, `smoke`, `clean`, `help`.
- [x] Add a tiny smoke test: `inputs/smoke/align-segment.json` + `inputs/smoke/frames/shot_NNNN.png` + `inputs/smoke/narration.mp3` that runs end-to-end on an empty Hel home in <90 s.
      `bin/make-smoke-fixture.sh` generates the fixture (inputs/ is gitignored); `scripts/smoke` runs it. Measured 1 s.
- [x] Verify shellcheck at severity=warning is clean for `bin/*.sh`, `lib/*.sh`, `scripts/check`, `githooks/pre-push`.
      shellcheck 0.10.0 installed in `~/.local/bin`; one real error found and fixed (`bin/mix-audio.sh` SC1087,
      `$music_vol[music]` → `${music_vol}[music]`). `scripts/check` no longer prints the skip WARN. Verified clean.
- [x] 0.1.0 scaffold.
- [x] copy auth.json + gh + tea configs from Hel so opencode does not need forced --model
