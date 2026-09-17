# TODO

## Open

- [ ] Add `--dry-run` flag to every `bin/` script — print the planned ffmpeg command, do not invoke.
- [ ] Add `bin/extract-segment-duration.sh` — read aligner JSON via jq and emit `inputs/durations.tsv` for the orchestrator.
- [ ] Document the `HSA_OVERRIDE_GFX_VERSION` invariant for AMD users (irrelevant here since we don't touch the GPU).
- [ ] Add `bin/make-srt.sh` — generate SRT captions from aligner JSON (sub-second precision, words coalesced into ~2 second captions).
- [ ] Add a `Makefile` or `justfile` wrapper for callers who don't want to type `bin/render-master.sh` directly.
- [ ] Add a tiny smoke test: `inputs/smoke/align-segment.json` + `inputs/smoke/frames/p1.png` + `inputs/smoke/narration.mp3` that runs end-to-end on an empty Hel home in <90 s.

## Done

- [x] 0.1.0 scaffold.
- [x] copy auth.json + gh + tea configs from Hel so opencode does not need forced --model
