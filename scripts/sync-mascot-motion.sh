#!/usr/bin/env bash
# BRD-001: copy the mascot's motion data, fixtures and rig from loci-client
# design/, and the model and still from its build output, into the app.
#
# Usage: scripts/sync-mascot-motion.sh [path-to-loci-client]   (default: ../loci-client)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
client="${1:-$repo/../loci-client}"
here="$repo/loci/loci/Resources/Mascot3D"
mkdir -p "$here"
for f in mascot-motion.json mascot-motion.fixtures.json mascot-rig.json; do
  cp "$client/design/$f" "$here/$f"
done
# The model and the still are build output there (git-ignored); copy them
# only when present: tools/brand/mascot_3d.py and tools/brand/mascot-still.mjs.
model="$client/tools/brand/out/mascot-3d/Mascot.usdz"
still="$client/tools/brand/out/mascot-still/mascot-3d-still.png"
[ -f "$model" ] && cp "$model" "$here/" || echo "no $model; model left as is" >&2
[ -f "$still" ] && cp "$still" "$here/" || echo "no $still; still left as is" >&2
"$repo/scripts/mascot-motion-guard.sh" "$client/design"
