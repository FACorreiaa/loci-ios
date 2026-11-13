#!/usr/bin/env bash
# BRD-001: prove the App Store build carries no 3D mascot.
#
# Builds the app for the simulator in Release and in Beta, then checks each
# .app for the mascot's files (Mascot.usdz, mascot-*.json, the 3D still) and
# for its Swift types (Mascot3DView, MascotStage, MascotMotion) in the binary.
#
#   Release must contain none of them.
#   Beta must contain all of them — the positive control, so this check
#   cannot pass by looking in the wrong place.
#
# Usage: scripts/verify-release-no-mascot3d.sh [derived-data-dir]
# The DerivedData directory must sit outside the repo (SwiftLint's run phase
# lints anything under the worktree).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
dd="${1:-${TMPDIR:-/tmp}/loci-mascot3d-verify}"
case "$dd" in "$repo"/*) echo "DerivedData must be outside $repo" >&2; exit 2 ;; esac

files=(Mascot.usdz mascot-motion.json mascot-motion.fixtures.json mascot-rig.json mascot-3d-still.png)
symbols=(Mascot3DView MascotStage MascotMotion)

build() { # scheme configuration
  xcodebuild build \
    -project "$repo/loci/loci.xcodeproj" \
    -scheme "$1" -configuration "$2" \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$dd" \
    CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO \
    -quiet >&2
  echo "$dd/Build/Products/$2-iphonesimulator/loci.app"
}

# Counts how many of the mascot's files and symbols are in the app.
inspect() { # app
  local app="$1" found=0 f s
  for f in "${files[@]}"; do
    if [ -n "$(find "$app" -name "$f" -print -quit)" ]; then
      echo "  file   $f" >&2; found=$((found + 1))
    fi
  done
  # Swift type names survive in metadata and mangled symbols, stripped or not.
  local dump
  dump="$(strings -a "$app/loci" "$app"/loci.debug.dylib 2>/dev/null || true)"
  for s in "${symbols[@]}"; do
    if grep -q "$s" <<<"$dump"; then
      echo "  symbol $s" >&2; found=$((found + 1))
    fi
  done
  echo "$found"
}

want=$(( ${#files[@]} + ${#symbols[@]} ))

echo "Beta (positive control)…" >&2
beta_app="$(build "loci Beta" Beta)"
beta=$(inspect "$beta_app")
if [ "$beta" -ne "$want" ]; then
  echo "FAIL: Beta has $beta of $want mascot files/symbols; the check would not see them in Release either." >&2
  exit 1
fi

echo "Release…" >&2
release_app="$(build loci Release)"
release=$(inspect "$release_app")
if [ "$release" -ne 0 ]; then
  echo "FAIL: Release carries $release mascot files/symbols (listed above)." >&2
  exit 1
fi

echo "ok: Release has none of the ${want} mascot files/symbols; Beta has all ${want}." >&2
