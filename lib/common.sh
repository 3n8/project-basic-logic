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

# ---- Output geometry (--format) ---------------------------------------------
# 16:9 is the existing 1920x1080 master. 9:16 is the short-form (vertical) master:
# the stills are fitted into SHORTS_W x SHORTS_H, never cropped, and the frame is
# filled behind them by a blurred copy of the same still (SHORTS_BLUR, gblur sigma
# in output pixels). SHORTS_MAX_SECONDS is the short-form length cap: a longer input
# is refused with a message, never truncated.
: "${FORMAT:=16:9}"
: "${SHORTS_W:=1080}"
: "${SHORTS_H:=1920}"
: "${SHORTS_BLUR:=40}"
: "${SHORTS_MAX_SECONDS:=60}"

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

# parse_format_flag "$@" — consume --format <16:9|9:16> / --format=<...>; the rest
# lands in ARGS[]. FORMAT defaults to the environment (then 16:9).
# Callers then do:  set -- ${ARGS[@]+"${ARGS[@]}"}
parse_format_flag() {
    ARGS=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --format)
                [ "$#" -ge 2 ] || die "--format needs a value: 16:9|9:16"
                FORMAT="$2"; shift 2 ;;
            --format=*) FORMAT="${1#--format=}"; shift ;;
            *) ARGS+=("$1"); shift ;;
        esac
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

# validate_format — die unless FORMAT is one of the two supported geometries.
validate_format() {
    case "$FORMAT" in
        16:9|9:16) ;;
        *) die "invalid format: '$FORMAT' (want 16:9 or 9:16)" ;;
    esac
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
