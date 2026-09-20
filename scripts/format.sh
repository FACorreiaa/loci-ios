#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_SWIFTLINT="$REPO_ROOT/.swiftlint.yml"
CONFIG_SWIFT_FORMAT="$REPO_ROOT/.swift-format"

SKIP_INSTALL=false
LINT_FIRST=false
LINT_ONLY=false
SWIFTLINT_REPORTER="xcode"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-install) SKIP_INSTALL=true ;;
    --lint-first)   LINT_FIRST=true ;;
    --lint-only)    LINT_ONLY=true ;;
    --reporter)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --reporter"
        exit 1
      fi
      SWIFTLINT_REPORTER="$2"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
  shift
done

# ---------- helpers ----------

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
dim()  { printf '\033[2m%s\033[0m\n' "$*"; }

timer_start() { SECONDS=0; }
timer_show()  { dim "  (${SECONDS}s)"; }

ensure_tool() {
  local formula=$1
  if command -v "$formula" >/dev/null 2>&1; then
    dim "$formula is installed ($(command -v "$formula"))"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    if brew list --formula 2>/dev/null | grep -qx "$formula"; then
      local outdated
      outdated=$(brew outdated --formula 2>/dev/null | grep -x "$formula" || true)
      if [ -n "$outdated" ]; then
        bold "Upgrading $formula..."
        brew upgrade "$formula"
      else
        dim "$formula is up to date"
      fi
    else
      bold "Installing $formula via Homebrew..."
      brew install "$formula"
    fi
  else
    echo "Error: $formula is not installed and Homebrew is not available."
    exit 1
  fi
}

find_swift_files() {
  find "$REPO_ROOT" \
    \( \
      -name .git \
      -o -name .build \
      -o -name .swiftpm \
      -o -name DerivedData \
      -o -name build \
      -o -name Pods \
      -o -name Carthage \
      -o -name '*.xcodeproj' \
      -o -name '*.xcworkspace' \
      -o -name loci-connect-proto \
    \) -prune \
    -o -name '*.swift' -not -name 'Package.swift' "$@"
}

# ---------- install / update ----------

if [ "$SKIP_INSTALL" = false ]; then
  bold "=== Checking tools ==="
  ensure_tool swiftlint
  if [ "$LINT_ONLY" = false ]; then
    ensure_tool swift-format
  fi
  echo ""
fi

run_swiftlint_check() {
  bold "=== Checking SwiftLint issues ==="
  timer_start
  cd "$REPO_ROOT"

  if [ "$SWIFTLINT_REPORTER" = "quiet" ]; then
    swiftlint lint --strict --quiet --config "$CONFIG_SWIFTLINT"
  else
    swiftlint lint --strict --config "$CONFIG_SWIFTLINT" --reporter "$SWIFTLINT_REPORTER"
  fi

  timer_show
  echo ""
}

if [ "$LINT_ONLY" = true ]; then
  run_swiftlint_check
  exit 0
fi

# ---------- count issues before ----------

bold "=== Counting SwiftLint issues ==="
timer_start
before=$( (cd "$REPO_ROOT" && swiftlint lint --quiet --config "$CONFIG_SWIFTLINT" 2>/dev/null || true) | wc -l | tr -d ' ')
echo "  Issues before: $before"
timer_show
echo ""

# ---------- formatting steps ----------

run_swift_format() {
  bold "=== Running swift-format ==="
  timer_start
  file_count=$(find_swift_files -print | wc -l | tr -d ' ')
  find_swift_files -print0 \
    | xargs -0 swift-format format --in-place --configuration "$CONFIG_SWIFT_FORMAT" 2>&1 \
    || true
  echo "  Formatted $file_count files"
  timer_show
  echo ""
}

run_swiftlint_fix() {
  bold "=== Running swiftlint --fix ==="
  timer_start
  cd "$REPO_ROOT"
  swiftlint lint --fix --quiet --config "$CONFIG_SWIFTLINT" 2>/dev/null || true
  echo "  Done"
  timer_show
  echo ""
}

if [ "$LINT_FIRST" = true ]; then
  run_swiftlint_fix
  run_swift_format
  run_swiftlint_fix
else
  run_swift_format
  run_swiftlint_fix
fi

# ---------- report remaining issues ----------

bold "=== Remaining SwiftLint issues ==="
after_output=$( (cd "$REPO_ROOT" && swiftlint lint --quiet --config "$CONFIG_SWIFTLINT" 2>/dev/null) || true)

if [ -z "$after_output" ]; then
  after=0
  echo "  No issues found!"
else
  after=$(echo "$after_output" | wc -l | tr -d ' ')
  echo "$after_output"
fi

echo ""
fixed=$((before - after))
if [ "$fixed" -gt 0 ]; then
  bold "Fixed $fixed issue(s) ($before → $after remaining)"
elif [ "$fixed" -eq 0 ]; then
  dim "No new issues fixed ($after remaining)"
else
  bold "Note: $after issues remaining (was $before — formatting may have surfaced new lint warnings)"
fi
