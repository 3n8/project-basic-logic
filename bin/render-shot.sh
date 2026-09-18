#!/usr/bin/env bash
# render-shot.sh — one PNG + duration → one MP4 freeze-frame clip.
# Usage: bin/render-shot.sh [--dry-run] [--format 16:9|9:16] <input.png> <duration_seconds> <output.mp4>
#
# Format — the geometry of the clip (--format <16:9|9:16>, or the FORMAT env var):
#   16:9  (default) the still is encoded as supplied
#   9:16            the still is fitted into SHORTS_W x SHORTS_H inside a blurred
#                   fill of itself; the picture is never cropped
#
# Idempotent. Same PNG + same duration + same format → same MP4 (modulo encoder determinism).

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_format_flag "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools
validate_format

[ "$#" -eq 3 ] || die "usage: render-shot.sh [--dry-run] [--format 16:9|9:16] <input.png> <duration_seconds> <output.mp4>"
in="$1"; dur="$2"; out="$3"

require_file "$in"
awk -v d="$dur" 'BEGIN { exit !(d > 0) }' || die "duration must be > 0; got: $dur"
make_dir "$(dirname "$out")"

stage "render-shot: $in → $out (${dur}s @ ${FPS}fps, format=$FORMAT)"

if [ "$FORMAT" = "9:16" ]; then
    # Vertical: a blurred, centre-cropped copy of the still fills the frame, then the
    # whole still is fitted on top of it. The picture itself is never cropped, and the
    # captions are burned onto this frame later, so nothing can be cropped away after.
    case "${SHORTS_W}x${SHORTS_H}" in
        *[!0-9x]*) die "SHORTS_W/SHORTS_H must be integers; got ${SHORTS_W}x${SHORTS_H}" ;;
    esac
    awk -v w="$SHORTS_W" -v h="$SHORTS_H" 'BEGIN { exit !(w > 0 && h > 0 && w % 2 == 0 && h % 2 == 0) }' \
        || die "SHORTS_W/SHORTS_H must be positive even numbers; got ${SHORTS_W}x${SHORTS_H}"
    awk -v b="$SHORTS_BLUR" 'BEGIN { exit !(b >= 0) }' \
        || die "SHORTS_BLUR must be a number >= 0; got $SHORTS_BLUR"

    fit="split=2[bgsrc][fgsrc];"
    fit+="[bgsrc]scale=${SHORTS_W}:${SHORTS_H}:force_original_aspect_ratio=increase,"
    fit+="crop=${SHORTS_W}:${SHORTS_H},gblur=sigma=${SHORTS_BLUR}[bg];"
    fit+="[fgsrc]scale=${SHORTS_W}:${SHORTS_H}:force_original_aspect_ratio=decrease[fg];"
    fit+="[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1,format=yuv420p[v]"

    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -loop 1 -framerate "$FPS" -t "$dur" -i "$in" \
        -filter_complex "$fit" -map "[v]" \
        -c:v libx264 -preset "$X264_PRESET" -tune "$X264_TUNE" -crf "$X264_CRF" \
        -an \
        -movflags +faststart \
        "$out"
else
    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -loop 1 -framerate "$FPS" -t "$dur" -i "$in" \
        -vf "format=yuv420p" \
        -c:v libx264 -preset "$X264_PRESET" -tune "$X264_TUNE" -crf "$X264_CRF" \
        -an \
        -movflags +faststart \
        "$out"
fi

wrote render-shot "$out"
