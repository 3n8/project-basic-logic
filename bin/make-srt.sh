#!/usr/bin/env bash
# make-srt.sh — coalesce word-level aligner JSON into ~2s SRT captions.
# Usage: bin/make-srt.sh <align-words.json> <out.srt>
#
# bash + jq + awk port of the former bin/make-srt.py; byte-identical output.
# Groups words until ~2s AND (sentence end OR ~2.8s), then flushes.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

[ "$#" -eq 2 ] || die "usage: make-srt.sh <align-words.json> <out.srt>"
in="$1"; out="$2"
require_file "$in"

if dry_run_enabled; then
    printf '[dry-run] make-srt: %s → %s\n' "$in" "$out" >&2
    exit 0
fi

make_dir "$(dirname "$out")"

jq -r '.segments[]
    | [ (.text // "" | tostring | gsub("^\\s+|\\s+$"; "")), (.start | tostring), (.end | tostring) ]
    | @tsv' "$in" |
awk -F'\t' '
BEGIN { TARGET = 2.0; MAX_S = 2.8; nc = 0; ph = 0 }

function fmt(t,   ms, h, m, s) {
    if (t < 0) t = 0
    ms = int(t * 1000 + 0.5)
    h = int(ms / 3600000); ms -= h * 3600000
    m = int(ms / 60000);   ms -= m * 60000
    s = int(ms / 1000);    ms -= s * 1000
    return sprintf("%02d:%02d:%02d,%03d", h, m, s, ms)
}

{
    if (ph == 0) { pstart = $2 + 0; ptext = $1 } else { ptext = ptext " " $1 }
    pend = $3 + 0
    ph++
    dur = pend - pstart
    punct = ($1 ~ /[.?!]$/)
    if (dur >= TARGET && (punct || dur >= MAX_S)) {
        nc++
        cstart[nc] = pstart; cend[nc] = pend; ctext[nc] = ptext
        ph = 0; ptext = ""
    }
}

END {
    if (ph > 0) {
        if (nc > 0 && (pend - pstart) < 1.0) {
            cend[nc] = pend
            ctext[nc] = ctext[nc] " " ptext
        } else {
            nc++
            cstart[nc] = pstart; cend[nc] = pend; ctext[nc] = ptext
        }
    }
    total = 0
    for (k = 1; k <= nc; k++) {
        s = cstart[k]; e = cend[k]
        if (e <= s) e = s + 0.04
        printf "%d\n%s --> %s\n%s\n\n", k, fmt(s), fmt(e), ctext[k]
        total += e - s
    }
    if (nc > 0) {
        printf "{\"cues\": %d, \"mean_s\": %.3f, \"out\": \"%s\"}\n", nc, total / nc, OUT > "/dev/stderr"
    }
}
' OUT="$out" > "$out"

wrote make-srt "$out"
