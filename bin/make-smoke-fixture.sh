#!/usr/bin/env bash
# make-smoke-fixture.sh — build a tiny end-to-end fixture under inputs/smoke/.
# Usage: bin/make-smoke-fixture.sh [dir]   (default: inputs/smoke)
#
# inputs/ is gitignored, so the fixture is generated rather than committed.
# Produces 3 shots × 2.0s = 6.0s of silence + 3 PNG frames + captions.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

DIR="${1:-inputs/smoke}"
if dry_run_enabled; then
    printf '[dry-run] make-smoke-fixture: build %s\n' "$DIR" >&2
    exit 0
fi

make_dir "$DIR/frames"

cat > "$DIR/align-segment.json" <<'JSON'
{
  "model": "smoke-fixture",
  "language": "English",
  "duration": 6.0,
  "segments": [
    {"text": "Smoke test one.", "start": 0.0, "end": 2.0},
    {"text": "Smoke test two.", "start": 2.0, "end": 4.0},
    {"text": "Smoke test three.", "start": 4.0, "end": 6.0}
  ]
}
JSON

cat > "$DIR/captions.srt" <<'SRT'
1
00:00:00,000 --> 00:00:02,000
Smoke test one.

2
00:00:02,000 --> 00:00:04,000
Smoke test two.

3
00:00:04,000 --> 00:00:06,000
Smoke test three.
SRT

colours=(0x1b1b1b 0x2a1f1f 0x1f2a2a)
for i in 1 2 3; do
    idx=$((i - 1))
    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -f lavfi -i "color=c=${colours[$idx]}:s=320x180:d=1" \
        -frames:v 1 "$DIR/frames/shot_$(printf '%04d' "$i").png"
done

run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
    -f lavfi -i "sine=frequency=220:sample_rate=24000:duration=6" \
    -af "volume=0.2" \
    -c:a libmp3lame -b:a 128k "$DIR/narration.mp3"

log "make-smoke-fixture: wrote $DIR"
