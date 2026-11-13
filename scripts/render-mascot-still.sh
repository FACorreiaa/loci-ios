#!/usr/bin/env bash
# Render the 3D mascot's first-paint still with RealityKit itself, so the
# swap from the still to the live view changes nothing on screen.
#
# Runs a Debug build on a booted 3x iPhone simulator, shows the mascot frozen
# at rest over black and over white (DesignPreview mascotStillBlack/White),
# photographs both and recovers the transparency
# (scripts/mascot_still_matte.py). Writes
# loci/loci/Resources/Mascot3D/mascot-3d-still.png (720 × 960).
#
# Usage: scripts/render-mascot-still.sh <simulator-udid> [derived-data-dir]
# Rerun after every model cut or lighting change.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
sim="${1:?usage: $0 <simulator-udid> [derived-data-dir]}"
dd="${2:-${TMPDIR:-/tmp}/loci-mascot-still-dd}"
case "$dd" in "$repo"/*) echo "DerivedData must be outside $repo" >&2; exit 2 ;; esac
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
bundle=com.fernandocorreia.loci

xcrun simctl bootstatus "$sim" -b >/dev/null
xcodebuild build -project "$repo/loci/loci.xcodeproj" -scheme loci -configuration Debug \
  -destination "platform=iOS Simulator,id=$sim" -derivedDataPath "$dd" \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO -quiet >&2
xcrun simctl install "$sim" "$dd/Build/Products/Debug-iphonesimulator/loci.app"

for bg in Black White; do
  xcrun simctl terminate "$sim" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$sim" "$bundle" -designPreview "mascotStill$bg" >/dev/null
  sleep 8
  xcrun simctl io "$sim" screenshot "$work/$bg.png" >/dev/null 2>&1
  sips -s format bmp "$work/$bg.png" --out "$work/$bg.bmp" >/dev/null
done
xcrun simctl terminate "$sim" "$bundle" >/dev/null 2>&1 || true

# The capture view is 240 × 320 points in the middle of the screen; at 3x
# that is 720 × 960 pixels.
read -r width height < <(sips -g pixelWidth -g pixelHeight "$work/Black.png" | awk '/pixel/ {print $2}' | xargs)
x=$(( (width - 720) / 2 ))
y=$(( (height - 960) / 2 ))
python3 -I "$repo/scripts/mascot_still_matte.py" "$work/Black.bmp" "$work/White.bmp" \
  "$repo/loci/loci/Resources/Mascot3D/mascot-3d-still.png" --crop "$x" "$y" 720 960
echo "wrote loci/loci/Resources/Mascot3D/mascot-3d-still.png" >&2
