#!/usr/bin/env bash
# render-master.sh — the orchestrator.
# Usage: bin/render-master.sh [--dry-run] <name> <master.mp4> [inputs_dir] [outputs_dir]
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
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

[ "$#" -ge 2 ] && [ "$#" -le 4 ] || die "usage: render-master.sh [--dry-run] <name> <master.mp4> [inputs_dir] [outputs_dir]"
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
if dry_run_enabled; then
    log "render-master: DRY RUN — printing planned commands, writing no media"
fi

# ---- 1. per-shot durations from aligner JSON ----------------------------
stage "1/6 building durations table"
DURATIONS_TSV="$RUN_DIR/durations.tsv"
write_durations_tsv "$IN_DIR/align-segment.json" "$DURATIONS_TSV"
shots_total="$(wc -l <"$DURATIONS_TSV" | tr -d ' ')"
log "render-master: $shots_total shots"

# ---- 2. render each shot freeze-frame -----------------------------------
stage "2/6 rendering $shots_total per-shot MP4s"
while IFS=$'\t' read -r shot dur; do
    [ -n "$shot" ] || continue
    src="$IN_DIR/frames/${shot}.png"
    [ -f "$src" ] || die "missing frame: $src"
    "$HERE/render-shot.sh" "$src" "$dur" "$RUN_DIR/${shot}.mp4"
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
if [ -f "$IN_DIR/captions.srt" ]; then
    if ! dry_run_enabled; then
        cp "$IN_DIR/captions.srt" "$RUN_DIR/captions.srt"
    fi
    "$HERE/burn-captions.sh" \
        "$RUN_DIR/video.mp4" "$RUN_DIR/captions.srt" "$RUN_DIR/captioned.mp4"
    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -i "$RUN_DIR/captioned.mp4" -i "$RUN_DIR/audio.wav" \
        -map 0:v -map 1:a \
        -c:v copy -c:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE" \
        -movflags +faststart \
        "$MASTER"
    if ! dry_run_enabled; then
        rm -f "$RUN_DIR/captioned.mp4"
    fi
else
    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -i "$RUN_DIR/video.mp4" -i "$RUN_DIR/audio.wav" \
        -map 0:v -map 1:a \
        -c:v copy -c:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE" \
        -movflags +faststart \
        "$MASTER"
fi

if dry_run_enabled; then
    log "render-master: DRY RUN complete — nothing written"
else
    log "render-master: $MASTER ready"
fi
