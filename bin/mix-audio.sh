#!/usr/bin/env bash
# mix-audio.sh — narration + music → stereo WAV mix.
# Usage: bin/mix-audio.sh [--dry-run] <narration.mp3> <music.ogg|-> <output.wav> [music_volume_linear]
#
# Music volume defaults to 0.18 (i.e. -15 dB) so it sits under narration.
# Pass '-' as the music path to skip music; output is narration-only.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/../lib/common.sh"
parse_common_flags "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}
require_tools

[ "$#" -ge 3 ] && [ "$#" -le 4 ] || die "usage: mix-audio.sh [--dry-run] <narration.mp3> <music.ogg|-> <output.wav> [volume]"
narration="$1"; music="$2"; out="$3"; music_vol="${4:-0.18}"

require_file "$narration"
make_dir "$(dirname "$out")"

stage "mix-audio: $narration + $music (×$music_vol) → $out"

if [ "$music" = "-" ]; then
    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -i "$narration" \
        -ar 48000 -ac 2 -c:a pcm_s24le \
        "$out"
else
    require_file "$music"
    run "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -y \
        -i "$narration" -i "$music" \
        -filter_complex "[1:a]volume=${music_vol}[music];[0:a][music]amix=inputs=2:duration=first:dropout_transition=0[mix]" \
        -map "[mix]" \
        -ar 48000 -ac 2 -c:a pcm_s24le \
        "$out"
fi

wrote mix-audio "$out"
