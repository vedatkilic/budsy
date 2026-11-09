#!/bin/bash
set -euo pipefail

# Regenerates the README / website images in docs/screenshots from the app's
# own offscreen renderer, so they never drift from the UI and nobody has to
# screenshot a live panel. Run after ./build.sh:
#
#   scripts/readme-screenshots.sh
#
# Produces, for menu / dashboard / sound-anc / earbud-controls / equalizer, a
# light and a "-dark" PNG (the README picks one per colour scheme) with a soft
# shadow on a transparent background, and demo.gif, a short tour of the panel.
# Needs ImageMagick (magick) and ffmpeg.

cd "$(dirname "$0")/.."
OUT="docs/screenshots"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

./Budsy.app/Contents/MacOS/Budsy --preview "$WORK/raw" >/dev/null

# name-in-docs : name-from-the-renderer
PAGES="menu:quick dashboard:dashboard sound-anc:sound-anc earbud-controls:earbud-controls equalizer:equalizer"

shadowed() {  # <in> <out>: the panel with a drop shadow, transparent around it
  magick "$1" \( +clone -background black -shadow 30x22+0+14 \) +swap \
    -background none -layers merge +repage -strip "$2"
}

for pair in $PAGES; do
  doc="${pair%%:*}"; raw="${pair##*:}"
  shadowed "$WORK/raw/$raw-light.png" "$OUT/$doc.png"
  shadowed "$WORK/raw/$raw-dark.png"  "$OUT/$doc-dark.png"
done

# The tour: each page centred on the same canvas so the GIF doesn't jump.
i=0
for raw in quick dashboard sound-anc earbud-controls equalizer about; do
  shadowed "$WORK/raw/$raw-light.png" "$WORK/panel.png"
  magick -size 1040x1400 gradient:'#EEF2F7-#D9E3F0' "$WORK/panel.png" \
    -gravity center -composite "$WORK/frame_$i.png"
  i=$((i + 1))
done
ffmpeg -y -loglevel error -framerate 1/1.6 -i "$WORK/frame_%d.png" \
  -vf "scale=520:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
  -loop 0 "$OUT/demo.gif"

ls -la "$OUT"
