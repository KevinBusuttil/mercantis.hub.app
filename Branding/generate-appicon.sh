#!/usr/bin/env bash
#
# Rasterise NeuradixAtlas-AppIcon.svg into the macOS AppIcon.appiconset and
# write a matching Contents.json. Run on a machine with an SVG rasteriser:
#   • rsvg-convert   (brew install librsvg)        ← preferred
#   • cairosvg       (pip install cairosvg)
#   • inkscape       (brew install --cask inkscape)
#
# Usage:  ./Branding/generate-appicon.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."
SVG="Branding/NeuradixAtlas-AppIcon.svg"
OUT="mercantis hub/Assets.xcassets/AppIcon.appiconset"

render() { # render <pixels> <outfile>
  local px="$1" file="$2"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "$px" -h "$px" "$SVG" -o "$file"
  elif command -v cairosvg >/dev/null 2>&1; then
    cairosvg "$SVG" -W "$px" -H "$px" -o "$file"
  elif command -v inkscape >/dev/null 2>&1; then
    inkscape "$SVG" --export-type=png -w "$px" -h "$px" -o "$file" >/dev/null 2>&1
  else
    echo "No SVG rasteriser found. Install librsvg (rsvg-convert), cairosvg, or inkscape." >&2
    exit 1
  fi
}

mkdir -p "$OUT"
# filename:pixels — covers every macOS slot plus the iOS universal 1024.
for entry in \
  icon_16x16.png:16 icon_16x16@2x.png:32 \
  icon_32x32.png:32 icon_32x32@2x.png:64 \
  icon_128x128.png:128 icon_128x128@2x.png:256 \
  icon_256x256.png:256 icon_256x256@2x.png:512 \
  icon_512x512.png:512 icon_512x512@2x.png:1024 \
  icon_1024.png:1024
do
  render "${entry##*:}" "$OUT/${entry%%:*}"
  echo "  rendered ${entry%%:*} (${entry##*:}px)"
done

cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024", "filename" : "icon_1024.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "idiom" : "universal", "platform" : "ios", "size" : "1024x1024", "filename" : "icon_1024.png" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "idiom" : "universal", "platform" : "ios", "size" : "1024x1024", "filename" : "icon_1024.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "AppIcon.appiconset populated. Rebuild the app to see the new icon."
