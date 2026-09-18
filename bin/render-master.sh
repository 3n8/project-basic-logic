#!/usr/bin/env bash
# render-master.sh — the orchestrator.
# Usage: bin/render-master.sh [--dry-run] [--captions burn|soft|off] [--format 16:9|9:16] <name> <master.mp4> [inputs_dir] [outputs_dir]
#
# Captions — pick a mode per render (--captions <mode>, or the CAPTIONS env var):
#   burn  (default) burned into the picture; always visible, matches a Shorts-style look
#   soft            a separate, switchable subtitle track next to the audio
#   off             no subtitles in the master at all
# Captions are only used when inputs/captions.srt exists.
#
# Format — pick the output geometry (--format <16:9|9:16>, or the FORMAT env var):
#   16:9  (default) the master keeps the stills as supplied
#   9:16            a vertical Shorts/Reels/TikTok master (SHORTS_W x SHORTS_H):
#                   each still is fitted into the vertical frame, never cropped,
#                   over a blurred fill of itself. A 9:16 run longer than
#                   SHORTS_MAX_SECONDS is refused — the audio is never truncated.
#
# Default inputs_dir=./inputs, outputs_dir=./outputs.
# Reads:
#   inputs/align-segment.json    word/phrase timestamps from qwen3-aligner
#   inputs/frames/shot_NNNN.png  one PNG per shot (0001..NNNN)
#   inputs/narration.mp3         voice track from qwen3-tts
#   inputs/music.ogg             optional bed (skip if absent)
#   inputs/captions.srt          optional SRT (skip if absent)
# Writes to outputs/<name>/:
#   shot_NNNN.mp4   per-shot freeze-frame clips
#   video.mp4       stitched
#   audio.wav       mixed + loudness-normalized
#   captions.srt    echoed
#   master.mp4      final
#
# --dry-run prints every planned ffmpeg command and writes no media.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"

# Caption mode: burn (default) | soft | off. Accepts --captions <mode> or --captions=<mode>,
# or the CAPTIONS environment variable. The command line wins over the environment.
CAPTIONS="${CAPTIONS:-burn}"
_render_args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --captions)
            [ "$#" -ge 2 ] || die "--captions needs a value: burn|soft|off"
            CAPTIONS="$2"
            shift 2
            ;;
        --captions=*) CAPTIONS="${1#--captions=}"; shift ;;
        *) _render_args+=("$1"); shift ;;
    esac
done
set -- ${_render_args[@]+"${_render_args[@]}"}

# Output geometry: 16:9 (default) | 9:16. Accepts --format <f>, --format=<f> or FORMAT=<f>.
parse_format_flag "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}

parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools
validate_format

case "$CAPTIONS" in
    burn|soft|off) ;;
    *) die "invalid captions mode: '$CAPTIONS' (want burn|soft|off)" ;;
esac

[ "$#" -ge 2 ] && [ "$#" -le 4 ] || die "usage: render-master.sh [--dry-run] [--captions burn|soft|off] [--format 16:9|9:16] <name> <master.mp4> [inputs_dir] [outputs_dir]"
NAME="$1"; MASTER="$2"
IN_DIR="${3:-inputs}"; OUT_DIR="${4:-outputs}"

# Sub-scripts must see the same mode.
export DRY_RUN

require_dir "$IN_DIR"
require_file "$IN_DIR/align-segment.json"
require_dir "$IN_DIR/frames"
require_file "$IN_DIR/narration.mp3"

RUN_DIR="$(ensure_layout "$NAME" "$OUT_DIR")"
log "render-master: run directory = $RUN_DIR"
log "render-master: format = $FORMAT, captions = $CAPTIONS"
if dry_run_enabled; then
    log "render-master: DRY RUN — printing planned commands, writing no media"
fi

# ---- 1. per-shot durations from aligner JSON ----------------------------
stage "1/6 building durations table"
DURATIONS_TSV="$RUN_DIR/durations.tsv"
write_durations_tsv "$IN_DIR/align-segment.json" "$DURATIONS_TSV"
shots_total="$(wc -l <"$DURATIONS_TSV" | tr -d ' ')"
log "render-master: $shots_total shots"

# Short form has a hard length cap. The timeline is closed (shot durations sum to the
# narration length), so the sum is the master's length to the millisecond. A longer
# input is refused outright — truncating the audio would silently drop words.
if [ "$FORMAT" = "9:16" ]; then
    awk -v m="$SHORTS_MAX_SECONDS" 'BEGIN { exit !(m > 0) }' \
        || die "SHORTS_MAX_SECONDS must be a number > 0; got '$SHORTS_MAX_SECONDS'"
    total_s="$(awk -F'\t' '{ s += $2 } END { printf "%.3f", s }' "$DURATIONS_TSV")"
    awk -v t="$total_s" -v max="$SHORTS_MAX_SECONDS" 'BEGIN { exit !(t <= max) }' \
        || die "9:16 is capped at ${SHORTS_MAX_SECONDS}s but this input is ${total_s}s — refusing to truncate the audio; supply a short cut, or raise SHORTS_MAX_SECONDS deliberately"
    log "render-master: $total_s s is within the ${SHORTS_MAX_SECONDS}s short-form cap"
fi

# ---- 2. render each shot freeze-frame -----------------------------------
stage "2/6 rendering $shots_total per-shot MP4s"
while IFS=$'\t' read -r shot dur; do
    [ -n "$shot" ] || continue
    src="$IN_DIR/frames/${shot}.png"
    [ -f "$src" ] || die "missing frame: $src"
    "$HERE/render-shot.sh" --format "$FORMAT" "$src" "$dur" "$RUN_DIR/${shot}.mp4"
done <"$DURATIONS_TSV"

# ---- 3. concat per-shot MP4s --------------------------------------------
stage "3/6 stitching per-shot MP4s"
LIST="$RUN_DIR/concat.txt"
ABS_RUN="$(cd "$RUN_DIR" && pwd)"
awk -v dir="$ABS_RUN" '{ printf "file '\''%s/%s.mp4'\''\n", dir, $1 }' "$DURATIONS_TSV" > "$LIST"
"$HERE/stitch-shots.sh" "$LIST" "$RUN_DIR/video.mp4"

# ---- 4. mix narration + music (if present) -----------------------------
stage "4/6 mixing audio"
MUSIC="-"   # amix filter wants SOMETHING; "-" means narration-only.
if [ -f "$IN_DIR/music.ogg" ]; then
    MUSIC="$IN_DIR/music.ogg"
fi
"$HERE/mix-audio.sh" "$IN_DIR/narration.mp3" "$MUSIC" "$RUN_DIR/audio_raw.wav"

# ---- 5. EBU R128 normalize ---------------------------------------------
stage "5/6 loudness-normalising"
"$HERE/normalize-loudness.sh" "$RUN_DIR/audio_raw.wav" "$RUN_DIR/audio.wav"
if ! dry_run_enabled; then
    rm -f "$RUN_DIR/audio_raw.wav"
fi

# ---- 6. mux video + audio + (optional captions) ------------------------
stage "6/6 muxing final master"
SRC_VIDEO="$RUN_DIR/video.mp4"
HAVE_CAPTIONS=0
if [ -f "$IN_DIR/captions.srt" ] && [ "$CAPTIONS" != "off" ]; then
    HAVE_CAPTIONS=1
fi

if [ "$HAVE_CAPTIONS" = "1" ]; then
    if ! dry_run_enabled; then
        cp "$IN_DIR/captions.srt" "$RUN_DIR/captions.srt"
    fi
    if [ "$CAPTIONS" = "soft" ]; then
        "$HERE/burn-captions.sh" --format "$FORMAT" \
            "$RUN_DIR/video.mp4" "$RUN_DIR/captions.srt" "$RUN_DIR/captioned.mp4" --soft
    else
        "$HERE/burn-captions.sh" --format "$FORMAT" \
            "$RUN_DIR/video.mp4" "$RUN_DIR/captions.srt" "$RUN_DIR/captioned.mp4"
    fi
    SRC_VIDEO="$RUN_DIR/captioned.mp4"
    log "render-master: captions mode = $CAPTIONS"
else
    if [ ! -f "$IN_DIR/captions.srt" ]; then
        log "render-master: no $IN_DIR/captions.srt — master will have no subtitles"
    else
        log "render-master: captions mode = off — master will have no subtitles"
    fi
fi

# Map the subtitle stream only when there is one ('?' makes it optional).
run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
    -i "$SRC_VIDEO" -i "$RUN_DIR/audio.wav" \
    -map 0:v -map 0:s? -map 1:a \
    -c:v copy -c:s copy -c:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE" \
    -movflags +faststart \
    "$MASTER"

if [ "$HAVE_CAPTIONS" = "1" ] && ! dry_run_enabled; then
    rm -f "$RUN_DIR/captioned.mp4"
fi

if dry_run_enabled; then
    log "render-master: DRY RUN complete — no media written"
else
    log "render-master: $MASTER ready ($FORMAT)"
fi
