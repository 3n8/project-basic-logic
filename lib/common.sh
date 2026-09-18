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

# wrote <label> <path> — completion line that stays truthful in dry-run mode.
wrote() {
    if dry_run_enabled; then
        log "$1: would write $2"
    else
        log "$1: wrote $2"
    fi
}

# ---- Dry-run support --------------------------------------------------------
# --dry-run (or DRY_RUN=1) prints the exact planned command instead of running it.
: "${DRY_RUN:=0}"

dry_run_enabled() { [ "$DRY_RUN" = "1" ]; }

# run <cmd> [args...] — execute the command, or print it when dry-run is on.
run() {
    if dry_run_enabled; then
        printf '[dry-run] %s\n' "$*" >&2
        return 0
    fi
    "$@"
}

# make_dir <dir> — create a directory unless we are in dry-run.
make_dir() {
    if dry_run_enabled; then
        return 0
    fi
    mkdir -p "$1"
}

# parse_common_flags "$@" — consume --dry-run; remaining operands land in ARGS[].
# Callers then do:  set -- ${ARGS[@]+"${ARGS[@]}"}
ARGS=()
parse_common_flags() {
    ARGS=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --) shift; ARGS+=("$@"); break ;;
            *) ARGS+=("$1") ;;
        esac
        shift
    done
}

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
# ensure_layout <name> <out_root> — create outputs/<name> and print it.
ensure_layout() {
    local name="$1" out_root="$2"
    mkdir -p "$out_root/$name"
    printf '%s\n' "$out_root/$name"
}
