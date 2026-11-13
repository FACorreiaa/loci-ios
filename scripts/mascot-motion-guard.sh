#!/usr/bin/env bash
# BRD-001: the mascot's motion data, fixtures and rig are copies of
# loci-client design/. Fails when any copy has drifted.
#
# Usage: scripts/mascot-motion-guard.sh <path-to-loci-client/design>
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
design="${1:?usage: $0 <path-to-loci-client/design>}"
here="$repo/loci/loci/Resources/Mascot3D"
status=0
for f in mascot-motion.json mascot-motion.fixtures.json mascot-rig.json; do
  if ! cmp -s "$design/$f" "$here/$f"; then
    echo "drift: $here/$f differs from $design/$f — run scripts/sync-mascot-motion.sh" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "mascot motion copies match loci-client design/"
exit "$status"
