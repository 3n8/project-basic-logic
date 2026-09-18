#!/usr/bin/env bash
# make-placeholder-frames.sh — one uniquely coloured 1920x1080 PNG per cue,
# named for write_durations_tsv.
# Usage: bin/make-placeholder-frames.sh <cues.json> <frames_dir>
#
# bash port of the former bin/make-placeholder-frames.py; byte-identical PNGs.
# Colour index is `i % 13` (i.e. `i % (len(PALETTE) - 1)`); the 14th colour
# is intentionally unreachable — the Python source does the same thing, so
# we reproduce it instead of "fixing" it.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

[ "$#" -eq 2 ] || die "usage: make-placeholder-frames.sh <cues.json> <frames_dir>"
in="$1"; out="$2"
require_file "$in"

PALETTE=(
    "#1b1b1b" "#3d2b1f" "#2f4f4f" "#4a3728" "#1f3b4d"
    "#5c4033" "#2c3e50" "#3b2f2f" "#4b5320" "#2e1a47"
    "#3e2723" "#1a3a3a" "#4a1942" "#243447"
)

if dry_run_enabled; then
    n=$(jq -r '.segments | length' "$in")
    printf '[dry-run] make-placeholder-frames: %s → %s (%d PNGs)\n' "$in" "$out" "$n" >&2
    exit 0
fi

make_dir "$out"

n_segments=$(jq -r '.segments | length' "$in")
font="/usr/share/fonts/TTF/DejaVuSans.ttf"
n=0

for ((i = 0; i < n_segments; i++)); do
    name=$(printf 'shot_%04d' $((i + 1)))
    color="${PALETTE[$((i % 13))]}"
    dest="$out/${name}.png"

    cmd=("$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y
         -f lavfi -i "color=c=${color}:s=1920x1080:d=1")

    if [ -f "$font" ]; then
        cmd+=(-vf "drawtext=fontfile=${font}:text='${name}':fontcolor=white:fontsize=64:x=80:y=80")
    fi

    cmd+=(-frames:v 1 "$dest")

    run "${cmd[@]}"
    n=$((n + 1))
done

# Summary on stderr (Python printed to stdout); exact JSON shape preserved.
printf '{"frames": %d, "dir": "%s"}\n' "$n" "$out" >&2
wrote make-placeholder-frames "$out"
