#!/usr/bin/env bash
# group-cues.sh — pack word-level aligner JSON into semantic shot cues.
# Usage: bin/group-cues.sh <align-words.json> <cues.json>
#
# bash + jq + awk port of the former bin/group-cues.py; byte-identical output
# (verified on inputs/reference/{prefix,full}_align_words.json).
#
# Documented deviation: segments whose `text` is JSON `null` are skipped,
# matching Python's `if not text: continue` after `.strip()` — but avoiding
# `str(None)` keeping the literal word "None". Missing `text` keys are also
# skipped (same as the Python behaviour once `str("")` becomes "" after strip).
#
# Word text is assumed to contain no tabs or newlines (the typical aligner
# JSON contract); the same assumption holds for the Python source.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

[ "$#" -eq 2 ] || die "usage: group-cues.sh <align-words.json> <cues.json>"
in="$1"; out="$2"
require_file "$in"

if dry_run_enabled; then
    printf '[dry-run] group-cues: %s → %s\n' "$in" "$out" >&2
    exit 0
fi

make_dir "$(dirname "$out")"

# Top-level scalars: jq prints the raw value or the literal "null".
model=$(jq -r '.model // null' "$in")
language=$(jq -r '.language // null' "$in")
duration=$(jq -r '.duration // null' "$in")

# Filter segments (drop text:null, missing-text, empty-after-strip),
# then emit one TSV line per kept segment.
jq -r '
    .segments[] |
    (if has("text") then .text else "" end) as $raw |
    if $raw == null then empty
    else
        ($raw | tostring | gsub("^\\s+|\\s+$"; "")) as $s |
        if $s == "" then empty
        else [$s, .start, .end]
        end
    end |
    @tsv
' "$in" | \
LC_ALL=C awk -F'\t' -v MODEL="$model" -v LANGUAGE="$language" -v DURATION="$duration" '
BEGIN {
    # Byte-to-int lookup for UTF-8 → \uXXXX decoding and JSON escaping.
    for (i = 0; i < 256; i++) b2i[sprintf("%c", i)] = i
}

function fmt(x,    s) {
    s = sprintf("%.3f", x + 0)
    sub(/0+$/, "", s)
    if (s ~ /\.$/) s = s "0"
    return s
}

function round1(x) { return sprintf("%.1f", x + 0) }

function join_range(arr, lo, hi, sep,    i, result) {
    result = arr[lo]
    for (i = lo + 1; i <= hi; i++) result = result sep arr[i]
    return result
}

# tsv_unescape: reverse jq @tsv escaping (\\ \n \t \r). Required because
# jq @tsv escapes `\` as `\\` (RFC 4180-style), so without this `wt[i]`
# contains double backslashes wherever the source text had a single one.
function tsv_unescape(s,    t, i, n, c2) {
    t = ""
    n = length(s)
    i = 1
    while (i <= n) {
        if (substr(s, i, 1) == "\\") {
            c2 = substr(s, i + 1, 1)
            if      (c2 == "n") t = t "\n"
            else if (c2 == "t") t = t "\t"
            else if (c2 == "r") t = t "\r"
            else                t = t c2
            i += 2
        } else {
            t = t substr(s, i, 1)
            i++
        }
    }
    return t
}

function format_value(s) {
    if (s == "null") return "null"
    return "\"" json_escape(s) "\""
}

function json_escape(s,    t, i, n, b1, b2, b3, b4, cp, hi, lo) {
    t = ""
    n = length(s)
    i = 1
    while (i <= n) {
        b1 = b2i[substr(s, i, 1)]
        if (b1 < 0x80) {
            if (b1 == 0x22)      t = t "\\\""
            else if (b1 == 0x5C) t = t "\\\\"
            else if (b1 == 0x08) t = t "\\b"
            else if (b1 == 0x09) t = t "\\t"
            else if (b1 == 0x0A) t = t "\\n"
            else if (b1 == 0x0C) t = t "\\f"
            else if (b1 == 0x0D) t = t "\\r"
            else if (b1 <  0x20) t = t sprintf("\\u%04x", b1)
            else                 t = t sprintf("%c", b1)
            i++
        } else if (b1 >= 0xC0 && b1 <= 0xDF) {
            b2 = b2i[substr(s, i+1, 1)]
            cp = (b1 - 0xC0) * 64 + (b2 - 0x80)
            t = t sprintf("\\u%04x", cp)
            i += 2
        } else if (b1 >= 0xE0 && b1 <= 0xEF) {
            b2 = b2i[substr(s, i+1, 1)]
            b3 = b2i[substr(s, i+2, 1)]
            cp = (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
            t = t sprintf("\\u%04x", cp)
            i += 3
        } else if (b1 >= 0xF0 && b1 <= 0xF7) {
            b2 = b2i[substr(s, i+1, 1)]
            b3 = b2i[substr(s, i+2, 1)]
            b4 = b2i[substr(s, i+3, 1)]
            cp = (b1 - 0xF0) * 262144 + (b2 - 0x80) * 4096 + (b3 - 0x80) * 64 + (b4 - 0x80)
            hi = 0xD800 + int((cp - 0x10000) / 1024)
            lo = 0xDC00 + ((cp - 0x10000) % 1024)
            t = t sprintf("\\u%04x\\u%04x", hi, lo)
            i += 4
        } else {
            # Invalid UTF-8 lead byte; pass the byte through unchanged.
            t = t substr(s, i, 1)
            i++
        }
    }
    return t
}

# Read every kept segment as a word.
{
    nwords++
    wt[nwords] = tsv_unescape($1)
    ws[nwords] = $2 + 0
    we[nwords] = $3 + 0
    if (we[nwords] < ws[nwords]) {
        tmp = ws[nwords]; ws[nwords] = we[nwords]; we[nwords] = tmp
    }
    if (we[nwords] == ws[nwords]) we[nwords] = ws[nwords] + 0.04
}

END {
    # audio_dur: data["duration"] when truthy, else the last word end.
    # Python is `float(data.get("duration") or words[-1]["end"])`, so a
    # duration of 0 (as well as null/absent/false) takes the fallback.
    if (DURATION + 0 == 0) {
        audio_dur = (nwords > 0) ? we[nwords] : 0
    } else {
        audio_dur = DURATION + 0
    }

    # pack(): accumulate words, flush on punctuation / gap / hard cap.
    nshots = 0
    ncur = 0
    cur_first_start = 0
    for (i = 1; i <= nwords; i++) {
        ncur++
        cur_text[ncur] = wt[i]
        if (ncur == 1) cur_first_start = ws[i]
        cur_last_end = we[i]
        cur_dur = cur_last_end - cur_first_start

        nxt = (i + 1 <= nwords) ? i + 1 : 0
        gap = nxt ? (ws[nxt] - we[i]) : 0.0

        wt_r = wt[i]; sub(/[ \t]+$/, "", wt_r)
        punct = (wt_r ~ /\.$/ || wt_r ~ /\?$/ || wt_r ~ /!$/)
        comma = (wt_r ~ /,$/  || wt_r ~ /;$/  || wt_r ~ /:$/)

        do_flush = 0
        if (nxt == 0)                           do_flush = 1
        else if (punct && cur_dur >= 2.0)       do_flush = 1
        else if (gap   >= 0.30 && cur_dur >= 2.0) do_flush = 1
        else if (comma && cur_dur >= 3.0)       do_flush = 1
        else if (cur_dur >= 8.5)                do_flush = 1

        if (do_flush) {
            nshots++
            shots_text[nshots]  = join_range(cur_text, 1, ncur, " ")
            shots_start[nshots] = cur_first_start
            shots_end[nshots]   = cur_last_end
            ncur = 0
        }
    }

    # merge_short(shots, 1.5): tiny cues merge back into the previous one.
    nmerged = 0
    for (i = 1; i <= nshots; i++) {
        dur = shots_end[i] - shots_start[i]
        if (nmerged > 0 && dur < 1.5) {
            merged_end[nmerged] = shots_end[i]
            t = merged_text[nmerged] " " shots_text[i]
            sub(/^[ \t]+|[ \t]+$/, "", t)
            merged_text[nmerged] = t
        } else {
            nmerged++
            merged_text[nmerged]  = shots_text[i]
            merged_start[nmerged] = shots_start[i]
            merged_end[nmerged]   = shots_end[i]
        }
    }
    # If the first cue is still < 1.5 s and there are >= 2 cues, merge forward.
    if (nmerged >= 2 && (merged_end[1] - merged_start[1]) < 1.5) {
        merged_end[1] = merged_end[2]
        t = merged_text[1] " " merged_text[2]
        sub(/^[ \t]+|[ \t]+$/, "", t)
        merged_text[1] = t
        for (i = 2; i <= nmerged - 1; i++) {
            merged_text[i]  = merged_text[i+1]
            merged_start[i] = merged_start[i+1]
            merged_end[i]   = merged_end[i+1]
        }
        nmerged--
    }

    # Snap: first start = 0.0, last end = audio_dur, chain interiors.
    if (nmerged > 0) {
        merged_start[1]    = 0.0
        merged_end[nmerged] = audio_dur
        for (i = 2; i <= nmerged; i++) merged_start[i] = merged_end[i-1]
    }

    # Emit the JSON document (Python json.dumps(obj, indent=2) + "\n").
    print "{"
    printf "  \"model\": %s,\n", format_value(MODEL)
    printf "  \"language\": %s,\n", format_value(LANGUAGE)
    printf "  \"duration\": %s,\n", fmt(audio_dur)
    printf "  \"source_words\": %d,\n", nwords
    print "  \"segments\": ["
    for (i = 1; i <= nmerged; i++) {
        print "    {"
        printf "      \"id\": \"shot_%04d\",\n", i
        printf "      \"text\": \"%s\",\n", json_escape(merged_text[i])
        printf "      \"start\": %s,\n", fmt(merged_start[i])
        printf "      \"end\": %s,\n", fmt(merged_end[i])
        print "      \"score\": null"
        if (i < nmerged) print "    },"
        else             print "    }"
    }
    print "  ]"
    print "}"

    # Stats for the summary line — same key order and spacing as the Python dict.
    ndurs = 0
    for (i = 1; i <= nmerged; i++) { ndurs++; durs[ndurs] = merged_end[i] - merged_start[i] }

    # sorted copy (insertion-ish; small n so bubble sort is fine).
    for (i = 1; i <= ndurs; i++) sorted[i] = durs[i]
    for (i = ndurs - 1; i >= 1; i--)
        for (j = 1; j <= i; j++)
            if (sorted[j+1] < sorted[j]) {
                tmp = sorted[j]; sorted[j] = sorted[j+1]; sorted[j+1] = tmp
            }
    # Python: median = durs_sorted[n // 2]  (upper median for even n).
    median = sorted[int(ndurs / 2) + 1]

    count_lt_1 = 0
    count_8_25 = 0
    sum_d = 0
    min_d = (ndurs > 0) ? durs[1] : 0
    max_d = (ndurs > 0) ? durs[1] : 0
    for (i = 1; i <= ndurs; i++) {
        d = durs[i]
        if (d <  1)         count_lt_1++
        if (d >= 8 && d <= 25) count_8_25++
        sum_d += d
        if (d < min_d) min_d = d
        if (d > max_d) max_d = d
    }
    pct_lt_1s = (ndurs > 0) ? round1(100 * count_lt_1 / ndurs) : 0

    printf "{\"shots\": %d, \"words\": %d, \"median_s\": %s, \"min_s\": %s, \"max_s\": %s, \"pct_lt_1s\": %s, \"holds_8_25\": %d, \"sum_s\": %s, \"audio_s\": %s, \"out\": \"%s\"}\n", \
        nmerged, nwords, fmt(median), fmt(min_d), fmt(max_d), pct_lt_1s, count_8_25, fmt(sum_d), fmt(audio_dur), OUT > "/dev/stderr"
}
' OUT="$out" > "$out"

wrote group-cues "$out"
