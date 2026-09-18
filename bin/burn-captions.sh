#!/usr/bin/env bash
# burn-captions.sh — burn an SRT into the video, OR mux as a soft subtitle track.
# Usage: bin/burn-captions.sh [--dry-run] <input.mp4> <captions.srt> <output.mp4> [--soft]
#
# Default mode is burn-in (image-rendered text baked into the video).
# Pass --soft to keep SRT as a separate track instead.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

[ "$#" -ge 3 ] && [ "$#" -le 4 ] || die "usage: burn-captions.sh [--dry-run] <input.mp4> <captions.srt> <output.mp4> [--soft]"
in="$1"; srt="$2"; out="$3"; mode="${4:-}"

# In dry-run the upstream video/SRT were never written, so only enforce existence for real runs.
if ! dry_run_enabled; then
    require_file "$in"
    require_file "$srt"
fi
make_dir "$(dirname "$out")"

stage "burn-captions: $in + $srt → $out ($([ "$mode" = "--soft" ] && echo soft || echo burn))"

if [ "$mode" = "--soft" ]; then
    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -i "$in" -i "$srt" \
        -c:v copy -c:a copy \
        -c:s mov_text \
        -metadata:s:s:0 language=und \
        -movflags +faststart \
        "$out"
else
    # Burn-in via the subtitles= video filter.
    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -i "$in" \
        -vf "subtitles='$srt':si=0:force_style='FontSize=22,PrimaryColour=&HFFFFFF,OutlineColour=&H000000,BorderStyle=1,Outline=2,Shadow=0'" \
        -c:v libx264 -preset "$X264_PRESET" -crf "$X264_CRF" \
        -c:a copy \
        -movflags +faststart \
        "$out"
fi

wrote burn-captions "$out"
