#!/usr/bin/env bash
# normalize-loudness.sh — EBU R128 two-pass loudness normalization.
# Usage: bin/normalize-loudness.sh [--dry-run] <input.wav> <output.wav>
#
# Two passes:
#   1) measure integrated/tp/lra with `loudnorm=...:print_format=json`
#   2) re-encode with measured values applied (broadcast-style precise mode)

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

[ "$#" -eq 2 ] || die "usage: normalize-loudness.sh [--dry-run] <input.wav> <output.wav>"
in="$1"; out="$2"
# In dry-run the upstream WAV was never written, so only enforce existence for real runs.
if ! dry_run_enabled; then
    require_file "$in"
fi
make_dir "$(dirname "$out")"

if dry_run_enabled; then
    printf '[dry-run] %s -i %s -af loudnorm=I=%s:TP=%s:LRA=%s:print_format=json -f null -\n' \
        "$FFMPEG_BIN" "$in" "$LOUDNORM_I" "$LOUDNORM_TP" "$LOUDNORM_LRA" >&2
    printf '[dry-run] %s -i %s -af loudnorm=<measured> -ar 48000 -ac 2 -c:a pcm_s24le %s\n' \
        "$FFMPEG_BIN" "$in" "$out" >&2
    exit 0
fi

stage "normalize-loudness: pass 1 (measure) for $in"

tmp="$(mktemp -t norm.XXXXXX.json)"
trap 'rm -f "$tmp"' EXIT

# Pass 1 — measure.
run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel info -i "$in" \
    -af "loudnorm=I=$LOUDNORM_I:TP=$LOUDNORM_TP:LRA=$LOUDNORM_LRA:print_format=json" \
    -f null - 2> "$tmp"
# ffmpeg prints a multi-line loudnorm JSON object on stderr. Take the last brace block.
# awk, not grep: the object spans lines, so a line-oriented -o would miss it.
measured="$(awk '
    /\{/ { buf = ""; inb = 1 }
    inb  { buf = buf $0 "\n" }
    /\}/ { if (inb) { last = buf; inb = 0 } }
    END  { printf "%s", last }
' "$tmp")"

[ -n "$measured" ] || die "pass 1 produced no loudnorm JSON"
log "normalize-loudness: measured: $measured"

# Pull the four measured values; default to zeros on missing keys.
measured_I="$(echo "$measured" | jq -r '.input_i // "0"')"
measured_TP="$(echo "$measured" | jq -r '.input_tp // "0"')"
measured_LRA="$(echo "$measured" | jq -r '.input_lra // "0"')"
measured_thresh="$(echo "$measured" | jq -r '.input_thresh // "-70"')"

# ---- usable_measure <value> — false for empty / inf / nan -------------------
# Digital silence measures as -inf; passing that to pass 2 makes libavfilter abort.
usable_measure() {
    case "$1" in
        "" | *[iI][nN][fF]* | *[nN][aA][nN]*) return 1 ;;
    esac
    return 0
}

stage "normalize-loudness: pass 2 (apply) → $out"

if usable_measure "$measured_I" && usable_measure "$measured_TP" && \
   usable_measure "$measured_LRA" && usable_measure "$measured_thresh"; then
    # Pass 2 — apply measured values (broadcast-style precise mode).
    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -i "$in" \
        -af "loudnorm=I=$LOUDNORM_I:TP=$LOUDNORM_TP:LRA=$LOUDNORM_LRA:\
measured_I=$measured_I:measured_TP=$measured_TP:measured_LRA=$measured_LRA:\
measured_thresh=$measured_thresh:linear=true:print_format=summary" \
        -ar 48000 -ac 2 -c:a pcm_s24le \
        "$out"
else
    log "normalize-loudness: measured values are not finite (silent input?); single-pass fallback"
    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -i "$in" \
        -af "loudnorm=I=$LOUDNORM_I:TP=$LOUDNORM_TP:LRA=$LOUDNORM_LRA:print_format=summary" \
        -ar 48000 -ac 2 -c:a pcm_s24le \
        "$out"
fi

wrote normalize-loudness "$out"
