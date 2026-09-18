# Goal

**Turn approved upstream inputs (narration, frames, timestamps, music, captions) into one reproducible `master.mp4` per video — bash + FFmpeg only, no creative layer.**

Same inputs in → same bytes out. Anything that doesn't satisfy that test doesn't belong here.

**What "no creative layer" means here:** no generative model, no per-frame
judgement, no artistic filters. A documented, fixed rule set is plumbing, not a
creative layer — `bin/make-srt.sh` (caption coalescing) and `bin/group-cues.sh`
(cue packing) are deterministic rule engines: same words in, same bytes out.
Everything in `bin/` is bash + FFmpeg + jq + awk. There is no Python.
