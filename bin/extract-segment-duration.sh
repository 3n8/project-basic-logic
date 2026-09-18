#!/usr/bin/env bash
# extract-segment-duration.sh — aligner JSON → durations.tsv for the orchestrator.
# Usage: bin/extract-segment-duration.sh <align-segment.json> [out.tsv]
#
# Emits one line per shot: shot_NNNN<TAB>seconds

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || die "usage: extract-segment-duration.sh <align-segment.json> [out.tsv]"
json="$1"; out="${2:-inputs/durations.tsv}"
require_file "$json"

if dry_run_enabled; then
    printf '[dry-run] extract-segment-duration: write_durations_tsv %s %s\n' "$json" "$out" >&2
    exit 0
fi

make_dir "$(dirname "$out")"
write_durations_tsv "$json" "$out"
wrote extract-segment-duration "$out"
