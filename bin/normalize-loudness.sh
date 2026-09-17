#!/usr/bin/env bash
# normalize-loudness.sh — EBU R128 two-pass loudness normalization.
# Usage: bin/normalize-loudness.sh <input.wav> <output.wav>
#
# Two passes:
#   1) measure integrated/tp/lra with `loudnorm=...:print_format=json`
#   2) re-encode with measured values applied (broadcast-style precise mode)

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
require_tools

[ "$#" -eq 2 ] || die "usage: normalize-loudness.sh <input.wav> <output.wav>"
in="$1"; out="$2"
require_file "$in"
mkdir -p "$(dirname "$out")"

stage "normalize-loudness: pass 1 (measure) for $in"

tmp="$(mktemp -t norm.XXXXXX.json)"
trap 'rm -f "$tmp"' EXIT

# Pass 1 — measure.
"$FFMPEG_BIN" -nostdin -hide_banner -loglevel info -i "$in" \
    -af "loudnorm=I=$LOUDNORM_I:TP=$LOUDNORM_TP:LRA=$LOUDNORM_LRA:print_format=json" \
    -f null - 2> "$tmp" || true
# ffmpeg prints a multi-line loudnorm JSON object on stderr. Take the last brace block.
measured="$(python3 -c 'import re,sys; t=open(sys.argv[1]).read(); b=re.findall(r"\{[^{}]*\}", t); print(b[-1] if b else "")' "$tmp")"

[ -n "$measured" ] || die "pass 1 produced no loudnorm JSON"
log "normalize-loudness: measured: $measured"

# Pull the four measured values; default to zeros on missing keys.
measured_I="$(echo "$measured" | jq -r '.input_i // "0"')"
measured_TP="$(echo "$measured" | jq -r '.input_tp // "0"')"
measured_LRA="$(echo "$measured" | jq -r '.input_lra // "0"')"
measured_thresh="$(echo "$measured" | jq -r '.input_thresh // "-70"')"

stage "normalize-loudness: pass 2 (apply) → $out"

# Pass 2 — apply measured values.
"$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
    -i "$in" \
    -af "loudnorm=I=$LOUDNORM_I:TP=$LOUDNORM_TP:LRA=$LOUDNORM_LRA:\
measured_I=$measured_I:measured_TP=$measured_TP:measured_LRA=$measured_LRA:\
measured_thresh=$measured_thresh:linear=true:print_format=summary" \
    -ar 48000 -ac 2 -c:a pcm_s24le \
    "$out"

log "normalize-loudness: wrote $out"
