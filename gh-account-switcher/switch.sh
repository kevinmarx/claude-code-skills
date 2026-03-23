#!/bin/bash
# gh-account-switcher: Auto-switch GitHub CLI accounts based on workspace directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/accounts.conf"

# Defaults
TARGET_PATH="$(pwd)"
CHECK_ONLY=false
QUIET=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      TARGET_PATH="$2"
      shift 2
      ;;
    --check)
      CHECK_ONLY=true
      shift
      ;;
    --quiet)
      QUIET=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Resolve to absolute path
TARGET_PATH="$(cd "$TARGET_PATH" 2>/dev/null && pwd || echo "$TARGET_PATH")"

# Find the expected account from accounts.conf
find_expected_account() {
  local path="$1"
  while IFS='|' read -r pattern account; do
    # Skip comments and blank lines
    pattern="$(echo "$pattern" | xargs)"
    account="$(echo "$account" | xargs)"
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue

    if [[ "$path" == "$pattern"* ]]; then
      echo "$account"
      return 0
    fi
  done < "$CONF_FILE"
  return 1
}

# Get the currently active gh account
get_current_account() {
  gh auth status 2>&1 | sed -n 's/.*Logged in to github\.com account \([^ ]*\).*/\1/p' | tr -d '()' | head -1 || true
}

EXPECTED=$(find_expected_account "$TARGET_PATH" || true)

if [[ -z "$EXPECTED" ]]; then
  if [[ "$QUIET" == true ]]; then
    echo "No mapping for $TARGET_PATH"
  else
    echo "No account mapping found for: $TARGET_PATH"
  fi
  exit 1
fi

CURRENT=$(get_current_account)

if [[ "$CHECK_ONLY" == true ]]; then
  if [[ "$CURRENT" == "$EXPECTED" ]]; then
    [[ "$QUIET" == true ]] && echo "OK: $CURRENT" || echo "Current: $CURRENT (correct)"
  else
    [[ "$QUIET" == true ]] && echo "MISMATCH: $CURRENT -> $EXPECTED" || echo "Current: $CURRENT, Expected: $EXPECTED"
  fi
  exit 0
fi

if [[ "$CURRENT" == "$EXPECTED" ]]; then
  [[ "$QUIET" != true ]] && echo "Already on $EXPECTED"
  exit 0
fi

# Perform the switch
if gh auth switch --user "$EXPECTED" 2>/dev/null; then
  [[ "$QUIET" == true ]] && echo "Switched to $EXPECTED" || echo "Switched from $CURRENT to $EXPECTED"
  exit 0
else
  echo "Failed to switch to $EXPECTED" >&2
  exit 1
fi
