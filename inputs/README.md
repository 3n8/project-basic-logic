# inputs/

Drop these here before running `bin/render-master.sh`:

| File | From | Required? |
|------|------|-----------|
| `align-segment.json` | `qwen3-aligner` HTTP API (`/v1/audio/align`) | yes |
| `frames/shot_NNNN.png` | ComfyUI on Hel | yes |
| `narration.mp3` | `qwen3-tts` HTTP API (`/v1/audio/speech`) | yes |
| `music.ogg` | external | optional |
| `captions.srt` | external — same text as the narration | optional |

`align-segment.json` is validated against `schemas/align-segment.schema.json`
by `scripts/check` on every push.
