# Changelog

## Unreleased

- Scaffold: `bin/{render-shot,stitch-shots,mix-audio,normalize-loudness,burn-captions,render-master}.sh`, `lib/common.sh`, `schemas/align-segment.schema.json`.
- `scripts/check` runs `shellcheck` on `bin/` and validates any `inputs/*.json` against the schema.
- `githooks/pre-push` invokes `scripts/check`.
- `opencode.json` enables the ponytail plugin (same as `envim`).
- Dual docs: `docs/PIPELINE.md`, `docs/SCRIPTS.md`.

## 0.1.0

- Project stand-up. No prior history.
