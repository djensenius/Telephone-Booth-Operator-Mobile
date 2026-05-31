#!/usr/bin/env bash
#
# capture-screenshots.sh — App Store screenshot capture for every platform.
#
# Builds an app target for its simulator (or the host, for macOS), launches it
# in the bundled demo mode (login-free, deterministic DemoData) via the
# `-uiTestDemoMode` / `-uiScreenshotTab` launch arguments, and writes one PNG
# per screen into fastlane/screenshots/<platform>/en-US/.
#
# Native simulator resolutions already match the App Store Connect display
# sizes, so no resizing is needed except for macOS (handled below). Every
# capture is dimension-checked before it is kept.
#
# Usage:  scripts/capture-screenshots.sh <iphone|ipad|tv|watch|vision|mac|all>
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="TelephoneBoothOperatorMobile.xcodeproj"
APP_ID="org.davidjensenius.TelephoneBoothOperatorMobile"
WATCH_APP_ID="org.davidjensenius.TelephoneBoothOperatorMobile.watch"
DD="/tmp/tbo-dd"
SHOTS="$ROOT/fastlane/screenshots"
LOCALE="en-CA"

log() { printf '\033[1;35m[shots]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[shots] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

udid_for() {
  xcrun simctl list devices available | grep -F "$1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

# Assert a PNG matches one of the accepted pixel sizes (W H, space-separated pairs).
assert_size() {
  local file="$1"; shift
  local w h
  w=$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$file" | awk '/pixelHeight/{print $2}')
  for pair in "$@"; do
    if [[ "$w $h" == "$pair" ]]; then log "  ✓ ${file##*/} = ${w}x${h}"; return 0; fi
  done
  die "${file##*/} is ${w}x${h}, expected one of: $*"
}

build_sim() {
  local scheme="$1" udid="$2"
  log "Building $scheme for simulator $udid …"
  xcodebuild -project "$PROJECT" -scheme "$scheme" \
    -destination "id=$udid" -configuration Debug \
    -derivedDataPath "$DD" build CODE_SIGNING_ALLOWED=NO >/tmp/tbo-build-"$scheme".log 2>&1 \
    || { tail -40 /tmp/tbo-build-"$scheme".log; die "build failed for $scheme"; }
}

# Capture a set of tabs on a booted simulator.
#   capture_sim <udid> <app_id> <product_name> <out_dir> <prefix> <sizes_csv> <tab...>
capture_sim() {
  local udid="$1" appid="$2" product="$3" out="$4" prefix="$5" sizes="$6"; shift 6
  local tabs=("$@")
  mkdir -p "$out"
  local app
  app=$(find "$DD/Build/Products" -maxdepth 2 -name "$product.app" -path '*simulator*' | head -1)
  [[ -n "$app" ]] || die "no $product.app found in derived data"
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$app"
  # Clean status bar (best-effort; unsupported platforms ignore this).
  xcrun simctl status_bar "$udid" override --time "9:41" \
    --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true

  IFS=',' read -r -a sizearr <<< "$sizes"
  if [[ ${#tabs[@]} -eq 0 ]]; then
    xcrun simctl terminate "$udid" "$appid" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$appid" -uiTestDemoMode YES >/dev/null
    sleep 18
    xcrun simctl io "$udid" screenshot "$out/${prefix}_01_home.png" >/dev/null 2>&1
    assert_size "$out/${prefix}_01_home.png" "${sizearr[@]}"
  else
    local i=1
    for tab in "${tabs[@]}"; do
      xcrun simctl terminate "$udid" "$appid" >/dev/null 2>&1 || true
      xcrun simctl launch "$udid" "$appid" -uiTestDemoMode YES -uiScreenshotTab "$tab" >/dev/null
      sleep 6
      local f
      f=$(printf "%s/%s_%02d_%s.png" "$out" "$prefix" "$i" "$tab")
      xcrun simctl io "$udid" screenshot "$f" >/dev/null 2>&1
      assert_size "$f" "${sizearr[@]}"
      i=$((i + 1))
    done
  fi
}

do_iphone() {
  local u; u=$(udid_for "iPhone 17 Pro Max"); [[ -n "$u" ]] || die "iPhone 17 Pro Max sim not found"
  build_sim TBOperatorMobile "$u"
  capture_sim "$u" "$APP_ID" TBOperatorMobile "$SHOTS/ios/$LOCALE" "iphone69" "1320 2868,1290 2796" \
    dashboard sessions messages stats system
}

do_ipad() {
  local u; u=$(udid_for "iPad Pro 13-inch (M5)"); [[ -n "$u" ]] || die "iPad Pro 13 sim not found"
  build_sim TBOperatorMobile "$u"
  capture_sim "$u" "$APP_ID" TBOperatorMobile "$SHOTS/ios/$LOCALE" "ipad13" "2064 2752,2048 2732" \
    dashboard sessions messages stats system
}

do_tv() {
  local u; u=$(udid_for "Apple TV 4K (3rd generation)"); [[ -n "$u" ]] || die "Apple TV 4K sim not found"
  build_sim TBOperatorMobileTV "$u"
  capture_sim "$u" "$APP_ID" TBOperatorMobileTV "$SHOTS/appletv/$LOCALE" "appletv" "3840 2160,1920 1080" \
    dashboard stats system
}

do_vision() {
  local u; u=$(udid_for "Apple Vision Pro"); [[ -n "$u" ]] || die "Apple Vision Pro sim not found"
  build_sim TBOperatorMobileVision "$u"
  capture_sim "$u" "$APP_ID" TBOperatorMobileVision "$SHOTS/visionos/$LOCALE" "vision" "3840 2160" \
    dashboard sessions stats system
}

do_watch() {
  local u; u=$(udid_for "Apple Watch Ultra 3"); [[ -n "$u" ]] || die "Apple Watch Ultra 3 sim not found"
  build_sim TBOperatorMobileWatch "$u"
  # Watch has no tab bar; capture the bespoke home dashboard only (no tab args).
  rm -f "$SHOTS/ios/$LOCALE"/watch_*.png
  capture_sim "$u" "$WATCH_APP_ID" TBOperatorMobileWatch "$SHOTS/ios/$LOCALE" "watch" "410 502,422 514,416 496,396 484"
}

# macOS: no simulator. Build, then run the .app once per tab and capture the
# window with `screencapture -l<windowid>` (Screen Recording permission must be
# granted to the controlling terminal once).
mac_window_id() {
  cat <<'SWIFT' | xcrun swift - 2>/dev/null
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
  let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
  let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let h = (b["Height"] as? Double) ?? 0
  if owner == "TB Operator" && h > 400 {
    print((w[kCGWindowNumber as String] as? Int) ?? 0)
    break
  }
}
SWIFT
}

mac_kill() {
  local pids
  pids=$(ps -axo pid,command | grep 'TBOperatorMobileMac.app/Contents/MacOS' | grep -v grep | awk '{print $1}' || true)
  for p in $pids; do kill "$p" 2>/dev/null || true; done
}

do_mac() {
  log "Building TBOperatorMobileMac for host …"
  xcodebuild -project "$PROJECT" -scheme TBOperatorMobileMac \
    -configuration Debug -derivedDataPath "$DD" build \
    CODE_SIGNING_ALLOWED=NO >/tmp/tbo-build-mac.log 2>&1 \
    || { tail -40 /tmp/tbo-build-mac.log; die "mac build failed"; }
  local app out
  app=$(find "$DD/Build/Products" -maxdepth 2 -name '*.app' -path '*Debug*' ! -path '*simulator*' | head -1)
  [[ -n "$app" ]] || die "mac .app not found"
  out="$SHOTS/mac/$LOCALE"; mkdir -p "$out"
  rm -f "$out"/mac_*.png
  local i=1
  for tab in dashboard sessions stats system; do
    mac_kill; sleep 1
    open -n "$app" --args -uiTestDemoMode YES -uiScreenshotTab "$tab"
    local wid="" tries=0
    while [[ -z "$wid" && $tries -lt 20 ]]; do
      sleep 1; wid=$(mac_window_id); tries=$((tries + 1))
    done
    [[ -n "$wid" ]] || { mac_kill; die "mac window not found for $tab"; }
    sleep 14
    local f
    f=$(printf "%s/mac_%02d_%s.png" "$out" "$i" "$tab")
    screencapture -x -o -l"$wid" "$f"
    [[ -f "$f" ]] || { mac_kill; die "mac capture produced no file for $tab"; }
    assert_size "$f" "2880 1800" "2560 1600" "1440 900" "1280 800"
    i=$((i + 1))
  done
  mac_kill
}

target="${1:-all}"
case "$target" in
  iphone) do_iphone ;;
  ipad)   do_ipad ;;
  tv)     do_tv ;;
  watch)  do_watch ;;
  vision) do_vision ;;
  mac)    do_mac ;;
  all)    do_iphone; do_ipad; do_watch; do_tv; do_vision; do_mac ;;
  *) die "unknown target '$target' (iphone|ipad|tv|watch|vision|mac|all)" ;;
esac
log "Done: $target"
