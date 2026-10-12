#!/usr/bin/env bash
# Frame device screenshots for the README: rounded corners, a hairline border and
# a soft shadow, on transparency so the pair sits on GitHub's light AND dark theme.
#
# GitHub strips inline `style=` from README HTML (verified: its markdown pipeline
# rewrites it to `style="max-width:100%"`), so the frame cannot come from CSS --
# it has to be in the pixels.
#
# Usage: scripts/frame-screenshots.sh <source.jpg> <out.png> [content-width]
set -euo pipefail

src=${1:?source image}
out=${2:?output png}
w=${3:-640}

pad=10        # transparent margin the shadow falls into
radius=26     # corner radius, roughly the device's own
border='#8b949e'

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# `>` = shrink only. A source narrower than `w` is left alone rather than upscaled.
magick "$src" -resize "${w}x>" -strip "$tmp/flat.png"
W=$(magick identify -format '%w' "$tmp/flat.png"); H=$(magick identify -format '%h' "$tmp/flat.png")

# Rounded-corner mask, radius `radius`, drawn as a white roundrect on black.
magick -size "${W}x${H}" xc:black -fill white \
  -draw "roundrectangle 0,0 $((W-1)),$((H-1)) $radius,$radius" "$tmp/mask.png"

# Hairline border first, so the alpha cut clips its outer half to a 1px inner edge.
magick "$tmp/flat.png" -fill none -stroke "$border" -strokewidth 2 \
  -draw "roundrectangle 1,1 $((W-3)),$((H-3)) $((radius-1)),$((radius-1))" "$tmp/bordered.png"

magick "$tmp/bordered.png" "$tmp/mask.png" -alpha off \
  -compose CopyOpacity -composite "$tmp/rounded.png"

magick "$tmp/rounded.png" \
  \( +clone -background black -shadow 40x10+0+6 \) +swap \
  -background none -layers merge +repage \
  -bordercolor none -border "$pad" -strip "$out"

echo "wrote $out -- $(magick identify -format '%wx%h %b' "$out")"
