#!/usr/bin/env bash
# burn-captions.sh — burn an SRT into the video, OR mux as a soft subtitle track.
# Usage: bin/burn-captions.sh [--dry-run] [--format 16:9|9:16] <input.mp4> <captions.srt> <output.mp4> [--soft]
#
# Default mode is burn-in (image-rendered text baked into the video).
# Pass --soft to keep SRT as a separate track instead.
#
# Format selects the burn-in style (--format <16:9|9:16>, or the FORMAT env var);
# it is ignored by --soft, where the player styles the track. libass scales the
# style font by the frame height, so the same FontSize renders much bigger on a
# 9:16 frame — both styles are fixed constants (CAPTION_STYLE_WIDE/TALL below).

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

[ "$#" -ge 3 ] && [ "$#" -le 4 ] || die "usage: burn-captions.sh [--dry-run] [--format 16:9|9:16] <input.mp4> <captions.srt> <output.mp4> [--soft]"
in="$1"; srt="$2"; out="$3"; mode="${4:-}"

# Burn-in look, per format. The 16:9 numbers are the original style; the 9:16 style
# is measured on a 1080x1920 frame: a 78 px ink line (against 69 px for the 16:9 style
# on 1920x1080) whose block sits in the bottom safe area, clear of the picture band.
: "${CAPTION_STYLE_WIDE:=FontSize=22,PrimaryColour=&HFFFFFF,OutlineColour=&H000000,BorderStyle=1,Outline=2,Shadow=0}"
: "${CAPTION_STYLE_TALL:=FontSize=14,PrimaryColour=&HFFFFFF,OutlineColour=&H000000,BorderStyle=1,Outline=2,Shadow=0,MarginV=42,MarginL=25,MarginR=25}"
style="$CAPTION_STYLE_WIDE"
[ "$FORMAT" = "9:16" ] && style="$CAPTION_STYLE_TALL"

# In dry-run the upstream video/SRT were never written, so only enforce existence for real runs.
if ! dry_run_enabled; then
    require_file "$in"
    require_file "$srt"
fi
make_dir "$(dirname "$out")"

stage "burn-captions: $in + $srt → $out ($([ "$mode" = "--soft" ] && echo soft || echo burn), format=$FORMAT)"

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
        -vf "subtitles='$srt':si=0:force_style='$style'" \
        -c:v libx264 -preset "$X264_PRESET" -crf "$X264_CRF" \
        -c:a copy \
        -movflags +faststart \
        "$out"
fi

wrote burn-captions "$out"
