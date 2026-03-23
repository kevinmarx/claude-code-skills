#!/usr/bin/env bash
# secret-scanner/scan.sh — Scan git content for leaked secrets
set -euo pipefail

SCAN_MODE="staged"
REPO_PATH="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staged) SCAN_MODE="staged"; shift ;;
    --all)    SCAN_MODE="all"; shift ;;
    --path)   REPO_PATH="${2:?Error: --path requires a directory}"; shift 2 ;;
    *)        echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

REPO_PATH="$(cd "$REPO_PATH" && pwd)"

if [[ ! -d "$REPO_PATH/.git" ]] && ! git -C "$REPO_PATH" rev-parse --git-dir &>/dev/null; then
  echo "Error: $REPO_PATH is not a git repository" >&2
  exit 2
fi

# Files to always ignore
IGNORE_PATTERN='(\.env$|\.env\.|\.secrets$|\.secrets\.)'

# Placeholder values to skip — matched case-insensitively
# Word-boundary patterns use [=: '"] before the placeholder to avoid matching substrings inside real keys
PLACEHOLDER_PATTERN='(YOUR_|PLACEHOLDER|CHANGEME|CHANGE_ME|INSERT_|REPLACE_|TODO|FIXME|xxxxxx|000000|[=: '\''"]example[_. '\''"]|[=: '\''"]sample[_. '\''"]|[=: '\''"]dummy[_. '\''"]|<[^>]+>|\$\{)'

# Collect files to scan
if [[ "$SCAN_MODE" == "staged" ]]; then
  FILES=$(git -C "$REPO_PATH" diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
else
  FILES=$(git -C "$REPO_PATH" ls-files 2>/dev/null || true)
fi

if [[ -z "$FILES" ]]; then
  exit 0
fi

FOUND=0

scan_line() {
  local file="$1"
  local line_num="$2"
  local line="$3"

  # Skip comment lines
  local trimmed="${line#"${line%%[![:space:]]*}"}"
  if [[ "$trimmed" == \#* ]]; then
    return
  fi

  # Skip lines with placeholder values
  if echo "$line" | grep -qiE "$PLACEHOLDER_PATTERN"; then
    return
  fi

  local match=""

  # JWT tokens
  if echo "$line" | grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'; then
    match="JWT token"
  fi

  # GitHub PATs
  if [[ -z "$match" ]] && echo "$line" | grep -qE 'gh[pousr]_[A-Za-z0-9]{30,}'; then
    match="GitHub PAT"
  fi

  # Anthropic keys
  if [[ -z "$match" ]] && echo "$line" | grep -qE 'sk-ant-[A-Za-z0-9_-]{20,}'; then
    match="Anthropic API key"
  fi

  # Generic sk- keys (but not sk-ant- which is caught above)
  if [[ -z "$match" ]] && echo "$line" | grep -qE 'sk-[A-Za-z0-9]{20,}'; then
    match="Secret key (sk-)"
  fi

  # AWS access keys
  if [[ -z "$match" ]] && echo "$line" | grep -qE 'AKIA[0-9A-Z]{16}'; then
    match="AWS access key"
  fi

  # Azure DevOps PATs (_password= or _authToken= with base64)
  if [[ -z "$match" ]] && echo "$line" | grep -qE '(_password|_authToken)\s*=\s*[A-Za-z0-9+/]{40,}={0,2}'; then
    match="Azure DevOps PAT"
  fi

  # Datadog keys (32-char hex after DD_API_KEY= or DD_APP_KEY=)
  if [[ -z "$match" ]] && echo "$line" | grep -qE 'DD_(API|APP)_KEY\s*=\s*[0-9a-fA-F]{32}'; then
    match="Datadog key"
  fi

  # Private keys
  if [[ -z "$match" ]] && echo "$line" | grep -qE 'BEGIN[[:space:]]+(RSA|DSA|EC|OPENSSH|PGP)?[[:space:]]*PRIVATE KEY'; then
    match="Private key"
  fi

  # Connection strings with passwords
  if [[ -z "$match" ]] && echo "$line" | grep -qiE '(connection.*string|server=|data source=).*password=[^;]{4,}'; then
    match="Connection string with password"
  fi

  # Generic password=/secret=/token= with actual values
  if [[ -z "$match" ]] && echo "$line" | grep -qiE '(password|secret|token|api_key|apikey|access_key)\s*[=:]\s*['\''"][^'\''"]{8,}['\''"]'; then
    match="Hardcoded credential"
  fi

  # Same but without quotes (e.g. in YAML/env-like contexts)
  if [[ -z "$match" ]] && echo "$line" | grep -qiE '(password|secret|token|api_key|apikey|access_key)\s*[=:]\s*[A-Za-z0-9_/+.=-]{12,}'; then
    match="Hardcoded credential"
  fi

  if [[ -n "$match" ]]; then
    echo "$file:$line_num  [$match]" >&2
    FOUND=1
    return 1
  fi
  return 0
}

while IFS= read -r file; do
  # Skip ignored files
  if echo "$file" | grep -qE "$IGNORE_PATTERN"; then
    continue
  fi

  local_path="$REPO_PATH/$file"

  # Get content based on scan mode
  if [[ "$SCAN_MODE" == "staged" ]]; then
    content=$(git -C "$REPO_PATH" show ":$file" 2>/dev/null || true)
  else
    if [[ -f "$local_path" ]]; then
      content=$(cat "$local_path")
    else
      continue
    fi
  fi

  if [[ -z "$content" ]]; then
    continue
  fi

  line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    # Skip empty lines
    [[ -z "$line" ]] && continue
    scan_line "$file" "$line_num" "$line" || FOUND=1
  done <<< "$content"
done <<< "$FILES"

if [[ "$FOUND" -eq 1 ]]; then
  echo "" >&2
  echo "Secret scan failed — fix the above before committing." >&2
  exit 1
fi

exit 0
