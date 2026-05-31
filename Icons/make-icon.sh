#!/usr/bin/env bash
#
# Render the PNG source artwork into flat and layered Apple app-icon assets.
#
# The generated source background is stripped away. All targets use only two
# layers: the gt3pro-style background and the extracted brushstroke foreground.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONS="$ROOT/Icons"
SOURCE="$ICONS/AppIconSource.png"
DEFAULT_REFERENCE_BACKGROUND="$HOME/Developer/gt3pro/Icons/scooter-bkgrd.png"
REFERENCE_BACKGROUND="${REFERENCE_BACKGROUND:-}"

if ! command -v magick >/dev/null 2>&1; then
  echo "magick not found — brew install imagemagick" >&2
  exit 1
fi

if [[ ! -f "$SOURCE" ]]; then
  echo "missing $SOURCE" >&2
  exit 1
fi

mkdir -p "$ICONS"

BACKGROUND="$ICONS/AppIcon-background.png"
FOREGROUND="$ICONS/AppIcon-foreground.png"
COMPOSITE="$ICONS/AppIcon-composite.png"
MASK="$ICONS/.AppIcon-mask.png"

if [[ -z "$REFERENCE_BACKGROUND" && -f "$DEFAULT_REFERENCE_BACKGROUND" ]]; then
  REFERENCE_BACKGROUND="$DEFAULT_REFERENCE_BACKGROUND"
fi

if [[ -n "$REFERENCE_BACKGROUND" ]]; then
  magick "$REFERENCE_BACKGROUND" -resize 1024x1024! -depth 8 "$BACKGROUND"
elif [[ ! -f "$BACKGROUND" ]]; then
  # Warm parchment fallback — complements sumi-e ink and avoids the
  # "squircle jail" effect of a near-white background on macOS.
  magick -size 1024x1024 "xc:#E8D5B7" -depth 8 "$BACKGROUND"
fi

magick "$SOURCE" -resize 1024x1024! \
  -alpha off \
  -colorspace Gray \
  -negate \
  -level 34%,82% \
  -blur 0x0.25 \
  "$MASK"

magick "$SOURCE" -resize 1024x1024! "$MASK" \
  -compose CopyOpacity \
  -composite \
  -depth 8 \
  "$FOREGROUND"

magick "$BACKGROUND" "$FOREGROUND" -composite -depth 8 "$COMPOSITE"

# Dark- and tinted-appearance composites for the iOS 18+ app icon. The
# brushstroke foreground is recoloured white so it stays legible on a dark
# field; the tinted variant is a grayscale mask the system colourises.
DARK_COMPOSITE="$ICONS/AppIcon-dark.png"
TINTED_COMPOSITE="$ICONS/AppIcon-tinted.png"
FG_WHITE="$ICONS/.AppIcon-fg-white.png"
BG_DARK="$ICONS/.AppIcon-bg-dark.png"

magick "$FOREGROUND" -fill white -colorize 100% -depth 8 "$FG_WHITE"
magick "$BACKGROUND" -modulate 22 -depth 8 "$BG_DARK"
magick "$BG_DARK" "$FG_WHITE" -compose over -composite -depth 8 "$DARK_COMPOSITE"
magick -size 1024x1024 xc:black "$FG_WHITE" -compose over -composite \
  -colorspace sRGB -depth 8 "$TINTED_COMPOSITE"

rm -f "$MASK" "$FG_WHITE" "$BG_DARK"

render_square() {
  local out="$1" size="$2"
  mkdir -p "$(dirname "$out")"
  magick "$COMPOSITE" -resize "${size}x${size}!" -depth 8 "$out"
  echo "  ${size}x${size} -> ${out#$ROOT/}"
}

render_layer() {
  local source="$1" out="$2" width="$3" height="$4" mode="${5:-contain}"
  mkdir -p "$(dirname "$out")"
  if [[ "$mode" == "cover" ]]; then
    magick "$source" -resize "${width}x${height}^" -gravity center -extent "${width}x${height}" -depth 8 "$out"
  else
    magick -size "${width}x${height}" xc:none \
      "$source" -resize "${width}x${height}" -gravity center -compose over -composite \
      -depth 8 "$out"
  fi
}

render_tv_composite() {
  local out="$1" width="$2" height="$3"
  mkdir -p "$(dirname "$out")"
  magick "$COMPOSITE" -resize "${width}x${height}^" -gravity center -extent "${width}x${height}" -depth 8 "$out"
}

write_json() {
  local file="$1" content="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$content" > "$file"
}

# iOS / iPadOS app icon: light, dark, and tinted appearances (iOS 18+).
IOS_SET="$ROOT/TBOperatorMobile/Assets.xcassets/AppIcon.appiconset"
render_square "$IOS_SET/AppIcon-1024.png" 1024
magick "$DARK_COMPOSITE" -resize 1024x1024! -depth 8 "$IOS_SET/AppIcon-1024-dark.png"
magick "$TINTED_COMPOSITE" -resize 1024x1024! -depth 8 "$IOS_SET/AppIcon-1024-tinted.png"
write_json "$IOS_SET/Contents.json" '{
  "images" : [
    { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "AppIcon-1024-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "AppIcon-1024-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}'

# watchOS uses a single flat icon (no dark/tinted appearances).
render_square "$ROOT/TBOperatorMobileWatch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" 1024

# macOS .icns-style appiconset.
MAC="$ROOT/TBOperatorMobileMac/Assets.xcassets/AppIcon.appiconset"
render_square "$MAC/icon_16x16.png" 16
render_square "$MAC/icon_16x16@2x.png" 32
render_square "$MAC/icon_32x32.png" 32
render_square "$MAC/icon_32x32@2x.png" 64
render_square "$MAC/icon_128x128.png" 128
render_square "$MAC/icon_128x128@2x.png" 256
render_square "$MAC/icon_256x256.png" 256
render_square "$MAC/icon_256x256@2x.png" 512
render_square "$MAC/icon_512x512.png" 512
render_square "$MAC/icon_512x512@2x.png" 1024

# visionOS layered icon: background + brushstroke only.
VISION="$ROOT/TBOperatorMobileVision/Assets.xcassets/AppIcon.solidimagestack"
rm -rf "$ROOT/TBOperatorMobileVision/Assets.xcassets/AppIcon.appiconset" "$VISION"
for layer in Back Front; do
  mkdir -p "$VISION/$layer.solidimagestacklayer/Content.imageset"
  write_json "$VISION/$layer.solidimagestacklayer/Contents.json" '{
  "info" : { "author" : "xcode", "version" : 1 }
}'
done
write_json "$VISION/Contents.json" '{
  "info" : { "author" : "xcode", "version" : 1 },
  "layers" : [
    { "filename" : "Front.solidimagestacklayer" },
    { "filename" : "Back.solidimagestacklayer" }
  ]
}'
render_layer "$BACKGROUND" "$VISION/Back.solidimagestacklayer/Content.imageset/background.png" 1024 1024 cover
render_layer "$FOREGROUND" "$VISION/Front.solidimagestacklayer/Content.imageset/foreground.png" 1024 1024 contain
write_json "$VISION/Back.solidimagestacklayer/Content.imageset/Contents.json" '{
  "images" : [{ "filename" : "background.png", "idiom" : "vision", "scale" : "2x" }],
  "info" : { "author" : "xcode", "version" : 1 }
}'
write_json "$VISION/Front.solidimagestacklayer/Content.imageset/Contents.json" '{
  "images" : [{ "filename" : "foreground.png", "idiom" : "vision", "scale" : "2x" }],
  "info" : { "author" : "xcode", "version" : 1 }
}'

# tvOS brand assets: background + brushstroke app-icon stacks.
TV="$ROOT/TBOperatorMobileTV/Assets.xcassets/AppIcon.brandassets"
rm -rf "$ROOT/TBOperatorMobileTV/Assets.xcassets/AppIcon.appiconset" "$TV"
write_json "$TV/Contents.json" '{
  "assets" : [
    { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
    { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
    { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
    { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}'

create_tv_stack() {
  local stack="$1" width="$2" height="$3" scale_json="$4"
  mkdir -p "$stack"
  write_json "$stack/Contents.json" '{
  "info" : { "author" : "xcode", "version" : 1 },
  "layers" : [
    { "filename" : "Front.imagestacklayer" },
    { "filename" : "Back.imagestacklayer" }
  ]
}'
  for layer in Back Front; do
    mkdir -p "$stack/$layer.imagestacklayer/Content.imageset"
    write_json "$stack/$layer.imagestacklayer/Contents.json" '{
  "info" : { "author" : "xcode", "version" : 1 }
}'
  done
  render_layer "$BACKGROUND" "$stack/Back.imagestacklayer/Content.imageset/back.png" "$width" "$height" cover
  render_layer "$FOREGROUND" "$stack/Front.imagestacklayer/Content.imageset/front.png" "$width" "$height" contain
  write_json "$stack/Back.imagestacklayer/Content.imageset/Contents.json" "{
  \"images\" : [{ \"filename\" : \"back.png\", \"idiom\" : \"tv\"$scale_json }],
  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }
}"
  write_json "$stack/Front.imagestacklayer/Content.imageset/Contents.json" "{
  \"images\" : [{ \"filename\" : \"front.png\", \"idiom\" : \"tv\"$scale_json }],
  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }
}"
}

create_tv_stack "$TV/App Icon - App Store.imagestack" 1280 768 ""

APP_STACK="$TV/App Icon.imagestack"
create_tv_stack "$APP_STACK" 800 480 ', "scale" : "2x"'
for layer in Back Front; do
  case "$layer" in
    Back) layer_source="$BACKGROUND"; file1x="back-1x.png"; file2x="back.png"; mode="cover" ;;
    Front) layer_source="$FOREGROUND"; file1x="front-1x.png"; file2x="front.png"; mode="contain" ;;
  esac
  render_layer "$layer_source" "$APP_STACK/$layer.imagestacklayer/Content.imageset/$file1x" 400 240 "$mode"
  write_json "$APP_STACK/$layer.imagestacklayer/Content.imageset/Contents.json" "{
  \"images\" : [
    { \"filename\" : \"$file1x\", \"idiom\" : \"tv\", \"scale\" : \"1x\" },
    { \"filename\" : \"$file2x\", \"idiom\" : \"tv\", \"scale\" : \"2x\" }
  ],
  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }
}"
done

TOP="$TV/Top Shelf Image.imageset"
TOP_WIDE="$TV/Top Shelf Image Wide.imageset"
render_tv_composite "$TOP/topshelf-1x.png" 1920 720
render_tv_composite "$TOP/topshelf-2x.png" 3840 1440
render_tv_composite "$TOP_WIDE/topshelf-wide-1x.png" 2320 720
render_tv_composite "$TOP_WIDE/topshelf-wide-2x.png" 4640 1440
write_json "$TOP/Contents.json" '{
  "images" : [
    { "filename" : "topshelf-1x.png", "idiom" : "tv", "scale" : "1x" },
    { "filename" : "topshelf-2x.png", "idiom" : "tv", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}'
write_json "$TOP_WIDE/Contents.json" '{
  "images" : [
    { "filename" : "topshelf-wide-1x.png", "idiom" : "tv", "scale" : "1x" },
    { "filename" : "topshelf-wide-2x.png", "idiom" : "tv", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}'

echo "Done. Rendered extracted brush artwork into flat and two-layer app-icon assets."
