# shellcheck shell=bash
# common.sh — shared helpers for project-basic-logic.
# Source me, do not run me: `source "$(dirname "$0")/../lib/common.sh"`

set -euo pipefail

# ---- Constants --------------------------------------------------------------
: "${FFMPEG_BIN:=ffmpeg}"
: "${FFPROBE_BIN:=ffprobe}"

# x264 is good and reproducible enough for stills + simple tweens.
: "${X264_PRESET:=slow}"
: "${X264_CRF:=20}"
: "${X264_TUNE:=stillimage}"

# EBU R128 targets for narration-heavy YouTube/Spotify ingest.
: "${LOUDNORM_I:=-16}"
: "${LOUDNORM_TP:=-1.5}"
: "${LOUDNORM_LRA:=11}"

# 24 fps is the house default for this pipeline; do not deviate without telling the user.
: "${FPS:=24}"

# Audio
: "${AUDIO_CODEC:=aac}"
: "${AUDIO_BITRATE:=192k}"

# ---- Logging ----------------------------------------------------------------
log()   { printf '[basic-logic] %s\n' "$*" >&2; }
stage() { printf '[stage] %s\n' "$*" >&2; }
die()   { printf '[FATAL] %s\n' "$*" >&2; exit 1; }

# ---- Tool presence ----------------------------------------------------------
need() {
    command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

require_tools() {
    need "$FFMPEG_BIN"
    need "$FFPROBE_BIN"
    need jq
}

# ---- Input validation -------------------------------------------------------
require_file() {
    [ -f "$1" ] || die "input not found: $1"
}

require_dir() {
    [ -d "$1" ] || die "input dir not found: $1"
}

# durations.tsv has lines: shot_id<TAB>seconds — used by the orchestrator.
write_durations_tsv() {
    local json="$1" out="$2"
    require_file "$json"
    jq -r '
        .segments
        | to_entries
        | map({shot: ("shot_" + ((.key + 1 | tostring) as $n | ("0000" + $n)[-4:])), dur: (.value.end - .value.start)})
        | .[]
        | [.shot, (.dur | tostring)] | @tsv
    ' "$json" > "$out"
}

# ---- Layout -----------------------------------------------------------------
ensure_layout() {
    local name="$1" out_root="$2"
    require_dir "$out_root" || mkdir -p "$out_root"
    mkdir -p "$out_root/$name"
    printf '%s\n' "$out_root/$name"
}
