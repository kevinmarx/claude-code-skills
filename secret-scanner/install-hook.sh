#!/usr/bin/env bash
# secret-scanner/install-hook.sh — Install scan.sh as a git pre-commit hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) REPO_PATH="${2:?Error: --path requires a directory}"; shift 2 ;;
    *)      echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

REPO_PATH="$(cd "$REPO_PATH" && pwd)"

# Support worktrees: resolve the actual hooks dir (make absolute)
HOOKS_DIR="$(cd "$REPO_PATH" && git rev-parse --git-path hooks 2>/dev/null)"
if [[ -z "$HOOKS_DIR" ]]; then
  echo "Error: $REPO_PATH is not a git repository" >&2
  exit 1
fi
# Make absolute if relative
if [[ "$HOOKS_DIR" != /* ]]; then
  HOOKS_DIR="$REPO_PATH/$HOOKS_DIR"
fi

mkdir -p "$HOOKS_DIR"

HOOK_FILE="$HOOKS_DIR/pre-commit"
MARKER="# secret-scanner-hook"
HOOK_BLOCK="$MARKER
bash \"$SCRIPT_DIR/scan.sh\" --staged --path \"$REPO_PATH\"
$MARKER-end"

if [[ -f "$HOOK_FILE" ]]; then
  # Check if already installed
  if grep -q "$MARKER" "$HOOK_FILE"; then
    # Remove old block and re-add (portable across macOS and Linux)
    tmp=$(mktemp)
    sed "/$MARKER/,/$MARKER-end/d" "$HOOK_FILE" > "$tmp" && mv "$tmp" "$HOOK_FILE"
  fi
  # Append to existing hook
  echo "" >> "$HOOK_FILE"
  echo "$HOOK_BLOCK" >> "$HOOK_FILE"
else
  # Create new hook
  cat > "$HOOK_FILE" << EOF
#!/bin/bash
$HOOK_BLOCK
EOF
fi

chmod +x "$HOOK_FILE"

echo "Secret scanner hook installed at $HOOK_FILE"
