#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-touchbar-demo.XXXXXX")"
OUTPUT="${PLUGIN_DIR}/assets/demo.gif"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

command -v /usr/bin/sips >/dev/null
command -v ffmpeg >/dev/null

/usr/bin/sips -s format png "${PLUGIN_DIR}/assets/demo-hidden.svg" --out "${WORK_DIR}/hidden.png" >/dev/null
/usr/bin/sips -s format png "${PLUGIN_DIR}/assets/preview.svg" --out "${WORK_DIR}/active.png" >/dev/null

/usr/bin/sed \
  -e 's/>99%</>94%</' \
  -e 's/>61%</>58%</' \
  -e 's/>昨日 2.5亿</>昨日 2.7亿</' \
  -e 's/>累计 75亿</>累计 75.2亿</' \
  "${PLUGIN_DIR}/assets/preview.svg" > "${WORK_DIR}/updated.svg"
/usr/bin/sips -s format png "${WORK_DIR}/updated.svg" --out "${WORK_DIR}/updated.png" >/dev/null

ffmpeg -y -loglevel error \
  -loop 1 -t 7 -i "${WORK_DIR}/hidden.png" \
  -loop 1 -t 7 -i "${WORK_DIR}/active.png" \
  -loop 1 -t 7 -i "${WORK_DIR}/updated.png" \
  -loop 1 -t 7 -i "${WORK_DIR}/hidden.png" \
  -filter_complex "
    [0:v]fps=10,format=rgba,setpts=PTS-STARTPTS[h0];
    [1:v]fps=10,format=rgba,setpts=PTS-STARTPTS[a0];
    [2:v]fps=10,format=rgba,setpts=PTS-STARTPTS[u0];
    [3:v]fps=10,format=rgba,setpts=PTS-STARTPTS[h1];
    [h0][a0]xfade=transition=fade:duration=0.45:offset=0.85[x1];
    [x1][u0]xfade=transition=fade:duration=0.3:offset=3.25[x2];
    [x2][h1]xfade=transition=fade:duration=0.5:offset=5.1,
      trim=duration=6,setpts=PTS-STARTPTS,scale=800:350:flags=lanczos,split[p0][p1];
    [p0]palettegen=max_colors=96:stats_mode=diff[pal];
    [p1][pal]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle
  " \
  -loop 0 "${OUTPUT}"

echo "Generated ${OUTPUT}"
