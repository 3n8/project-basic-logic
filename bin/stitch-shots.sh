#!/usr/bin/env bash
# stitch-shots.sh — concat a list of per-shot MP4s into one video.
# Usage: bin/stitch-shots.sh <concat_list.txt> <output.mp4>
#
# concat_list.txt must follow ffmpeg concat demuxer format:
#   file '/abs/path/shot_0001.mp4'
#   file '/abs/path/shot_0002.mp4'
#   ...
#
# Each line MUST be absolute or relative to the file; -safe 0 lets us use abs paths.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
require_tools

[ "$#" -eq 2 ] || die "usage: stitch-shots.sh <concat_list.txt> <output.mp4>"
list="$1"; out="$2"

require_file "$list"
mkdir -p "$(dirname "$out")"

stage "stitch-shots: $list → $out"

"$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
    -f concat -safe 0 -i "$list" \
    -c:v copy \
    -an \
    -movflags +faststart \
    "$out"

log "stitch-shots: wrote $out"
