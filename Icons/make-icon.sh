#!/usr/bin/env bash
#
#  make-icon.sh — render Icons/AppIcon.svg into every Assets.xcassets
#  AppIcon.appiconset across the project. Requires rsvg-convert (brew
#  install librsvg). Re-run whenever AppIcon.svg changes; the rendered
#  PNGs are committed alongside the SVG so contributors don't need the
#  toolchain locally.
#
#  Usage: ./Icons/make-icon.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/Icons/AppIcon.svg"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found — brew install librsvg" >&2
  exit 1
fi

render() {
  local out="$1" size="$2"
  mkdir -p "$(dirname "$out")"
  rsvg-convert --width "$size" --height "$size" --format png "$SVG" --output "$out"
  echo "  ${size}x${size} -> ${out#$ROOT/}"
}

# Single-image idioms (iOS / iPadOS / watchOS / visionOS) — Xcode wants
# a single 1024×1024 PNG and renders the rest at build time.
for set in TBOperatorMobile TBOperatorMobileWatch TBOperatorMobileVision; do
  target="$ROOT/$set/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
  render "$target" 1024
done

# macOS .icns needs every size pre-rendered.
MAC="$ROOT/TBOperatorMobileMac/Assets.xcassets/AppIcon.appiconset"
render "$MAC/icon_16x16.png"      16
render "$MAC/icon_16x16@2x.png"   32
render "$MAC/icon_32x32.png"      32
render "$MAC/icon_32x32@2x.png"   64
render "$MAC/icon_128x128.png"   128
render "$MAC/icon_128x128@2x.png" 256
render "$MAC/icon_256x256.png"   256
render "$MAC/icon_256x256@2x.png" 512
render "$MAC/icon_512x512.png"   512
render "$MAC/icon_512x512@2x.png" 1024

# tvOS uses a Brand Assets group rather than a flat AppIcon; the existing
# Contents.json keeps the placeholder, and the SVG is supplied here for
# future hand-rendered layered tiles.

echo "Done. Rendered AppIcon.svg into every Assets.xcassets."
