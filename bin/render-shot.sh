#!/usr/bin/env bash
# render-shot.sh — one PNG + duration → one MP4 freeze-frame clip.
# Usage: bin/render-shot.sh [--dry-run] <input.png> <duration_seconds> <output.mp4>
#
# Idempotent. Same PNG + same duration → same MP4 (modulo encoder determinism).

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

[ "$#" -eq 3 ] || die "usage: render-shot.sh [--dry-run] <input.png> <duration_seconds> <output.mp4>"
in="$1"; dur="$2"; out="$3"

require_file "$in"
awk -v d="$dur" 'BEGIN { exit !(d > 0) }' || die "duration must be > 0; got: $dur"
make_dir "$(dirname "$out")"

stage "render-shot: $in → $out (${dur}s @ ${FPS}fps)"

run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
    -loop 1 -framerate "$FPS" -t "$dur" -i "$in" \
    -vf "format=yuv420p" \
    -c:v libx264 -preset "$X264_PRESET" -tune "$X264_TUNE" -crf "$X264_CRF" \
    -an \
    -movflags +faststart \
    "$out"

wrote render-shot "$out"
