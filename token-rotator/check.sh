#!/bin/bash
# token-rotator/check.sh — Check token expiry and health across services
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/tokens.conf"
EXPIRY_WARNING_DAYS=7
NOW_EPOCH=$(date +%s)

# --- Flags ---
JSON_OUTPUT=false
QUIET_MODE=false

for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUTPUT=true ;;
    --quiet) QUIET_MODE=true ;;
    --help|-h)
      echo "Usage: check.sh [--json] [--quiet]"
      echo "  --json   Machine-readable JSON output"
      echo "  --quiet  Only show problems (expiring/expired/invalid)"
      exit 0
      ;;
  esac
done

# --- Result accumulators ---
declare -a RESULTS=()
HAS_EXPIRED=false
HAS_EXPIRING=false

# --- Helpers ---

has_jq() {
  command -v jq &>/dev/null
}

# Base64 decode that handles URL-safe base64 and missing padding
b64_decode() {
  local input="$1"
  # Replace URL-safe chars
  input="${input//-/+}"
  input="${input//_//}"
  # Add padding
  local pad=$(( 4 - ${#input} % 4 ))
  if [[ $pad -lt 4 ]]; then
    for ((i=0; i<pad; i++)); do input+="="; done
  fi
  echo "$input" | base64 -d 2>/dev/null
}

# Extract a JSON field without jq (fragile but functional fallback)
json_field() {
  local json="$1" field="$2"
  if has_jq; then
    echo "$json" | jq -r ".$field // empty" 2>/dev/null
  else
    # Grep-based fallback for simple flat JSON
    echo "$json" | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*[0-9]*" | head -1 | grep -o '[0-9]*$'
  fi
}

add_result() {
  local name="$1" status="$2" details="$3"
  RESULTS+=("${name}|${status}|${details}")

  case "$status" in
    "expired"|"invalid") HAS_EXPIRED=true ;;
    "expiring") HAS_EXPIRING=true ;;
  esac
}

# --- Validation Methods ---

check_gh_cli() {
  local name="$1"

  if ! command -v gh &>/dev/null; then
    add_result "$name" "invalid" "gh CLI not installed"
    return
  fi

  # Determine which account to check based on name
  local account_hint=""
  if [[ "$name" == *"kevinmarx"* ]]; then
    account_hint="kevinmarx"
  elif [[ "$name" == *"kemarx_microsoft"* ]]; then
    account_hint="kemarx_microsoft"
  fi

  local gh_output
  gh_output=$(gh auth status 2>&1) || true

  if [[ -z "$gh_output" ]]; then
    add_result "$name" "invalid" "gh auth returned no output"
    return
  fi

  # Look for the specific account in the output
  local found=false
  local logged_in=false
  local token_expiry=""

  if [[ -n "$account_hint" ]]; then
    # Check if this account appears in the output
    if echo "$gh_output" | grep -qi "$account_hint"; then
      found=true
      # Check if it says "Logged in" near the account reference
      local account_block
      account_block=$(echo "$gh_output" | grep -A5 -i "$account_hint" 2>/dev/null) || true
      if echo "$account_block" | grep -qi "logged in"; then
        logged_in=true
      fi
      # Check for token expiration info
      local expiry_line
      expiry_line=$(echo "$account_block" | grep -i "expir" 2>/dev/null) || true
      if [[ -n "$expiry_line" ]]; then
        token_expiry="$expiry_line"
      fi
    fi
  fi

  if ! $found; then
    # Fallback: check general auth status
    if echo "$gh_output" | grep -qi "logged in"; then
      add_result "$name" "valid" "Logged in (account not individually identified)"
    else
      add_result "$name" "invalid" "Not authenticated"
    fi
    return
  fi

  if $logged_in; then
    if [[ -n "$token_expiry" ]]; then
      # Try to detect if it says "expired"
      if echo "$token_expiry" | grep -qi "expired"; then
        add_result "$name" "expired" "Token expired — $(echo "$token_expiry" | xargs)"
      else
        add_result "$name" "valid" "Logged in — $(echo "$token_expiry" | xargs)"
      fi
    else
      add_result "$name" "valid" "Logged in"
    fi
  else
    add_result "$name" "invalid" "Not authenticated for $account_hint"
  fi
}

check_jwt_expiry() {
  local name="$1" source="$2"

  # Expand tilde
  source="${source/#\~/$HOME}"

  if [[ ! -f "$source" ]]; then
    add_result "$name" "invalid" "File not found: $source"
    return
  fi

  # Extract tokens from npmrc (look for _password or _authToken lines with JWT-like values)
  local tokens
  tokens=$(grep -oE '//[^:]+:_authToken=(.+)' "$source" 2>/dev/null | sed 's/.*_authToken=//' || true)

  if [[ -z "$tokens" ]]; then
    # Also try _password fields
    tokens=$(grep -oE '_password=([A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+)' "$source" 2>/dev/null | sed 's/_password=//' || true)
  fi

  if [[ -z "$tokens" ]]; then
    add_result "$name" "unchecked" "No JWT tokens found in $source"
    return
  fi

  local earliest_exp=""
  local earliest_detail=""

  while IFS= read -r token; do
    [[ -z "$token" ]] && continue

    # A JWT has 3 dot-separated parts; decode the payload (part 2)
    local parts
    IFS='.' read -ra parts <<< "$token"
    if [[ ${#parts[@]} -lt 3 ]]; then
      continue
    fi

    local payload
    payload=$(b64_decode "${parts[1]}")
    if [[ -z "$payload" ]]; then
      continue
    fi

    local exp
    exp=$(json_field "$payload" "exp")
    if [[ -z "$exp" ]]; then
      continue
    fi

    # Compare with current time
    local diff_seconds=$(( exp - NOW_EPOCH ))
    local diff_days=$(( diff_seconds / 86400 ))

    if [[ -z "$earliest_exp" ]] || [[ "$exp" -lt "$earliest_exp" ]]; then
      earliest_exp="$exp"
      if [[ $diff_seconds -le 0 ]]; then
        earliest_detail="expired|Expired $(( -diff_days )) days ago ($(date -r "$exp" '+%Y-%m-%d' 2>/dev/null || date -d "@$exp" '+%Y-%m-%d' 2>/dev/null || echo "epoch:$exp"))"
      elif [[ $diff_days -lt $EXPIRY_WARNING_DAYS ]]; then
        earliest_detail="expiring|Expires in ${diff_days}d ($(date -r "$exp" '+%Y-%m-%d' 2>/dev/null || date -d "@$exp" '+%Y-%m-%d' 2>/dev/null || echo "epoch:$exp"))"
      else
        earliest_detail="valid|Expires in ${diff_days}d ($(date -r "$exp" '+%Y-%m-%d' 2>/dev/null || date -d "@$exp" '+%Y-%m-%d' 2>/dev/null || echo "epoch:$exp"))"
      fi
    fi
  done <<< "$tokens"

  if [[ -n "$earliest_detail" ]]; then
    local status="${earliest_detail%%|*}"
    local detail="${earliest_detail#*|}"
    add_result "$name" "$status" "$detail"
  else
    add_result "$name" "unchecked" "Could not decode any JWTs from $source"
  fi
}

check_litellm_health() {
  local name="$1" env_var="$2"

  local val="${!env_var:-}"
  if [[ -z "$val" ]]; then
    add_result "$name" "invalid" "Env var $env_var is not set"
    return
  fi

  # Optionally hit litellm health endpoint
  if curl -sf --max-time 3 http://localhost:4000/health &>/dev/null; then
    add_result "$name" "valid" "$env_var is set, LiteLLM proxy healthy"
  else
    add_result "$name" "valid" "$env_var is set (LiteLLM proxy not reachable)"
  fi
}

check_datadog_validate() {
  local name="$1" env_var="$2"

  local val="${!env_var:-}"
  if [[ -z "$val" ]]; then
    add_result "$name" "invalid" "Env var $env_var is not set"
    return
  fi

  # Mask the value for display
  local masked="${val:0:4}...${val: -4}"
  add_result "$name" "valid" "$env_var is set (${masked})"
}

check_http_check() {
  local name="$1" env_var="$2"

  local val="${!env_var:-}"
  if [[ -z "$val" ]]; then
    add_result "$name" "invalid" "Env var $env_var is not set"
    return
  fi

  local masked="${val:0:4}...${val: -4}"
  add_result "$name" "valid" "$env_var is set (${masked})"
}

# --- Status symbol map ---

status_symbol() {
  case "$1" in
    valid)     echo "✓" ;;
    expiring)  echo "⚠" ;;
    expired|invalid) echo "✗" ;;
    unchecked) echo "?" ;;
    *)         echo "?" ;;
  esac
}

# --- Main: read config and run checks ---

if [[ ! -f "$CONF_FILE" ]]; then
  echo "Error: Config file not found: $CONF_FILE" >&2
  exit 1
fi

while IFS= read -r line; do
  # Skip comments and blank lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue

  # Parse: name | source | method
  IFS='|' read -r name source method <<< "$line"
  name=$(echo "$name" | xargs)
  source=$(echo "$source" | xargs)
  method=$(echo "$method" | xargs)

  case "$method" in
    gh_cli)           check_gh_cli "$name" ;;
    jwt_expiry)       check_jwt_expiry "$name" "$source" ;;
    litellm_health)   check_litellm_health "$name" "$source" ;;
    datadog_validate) check_datadog_validate "$name" "$source" ;;
    http_check)       check_http_check "$name" "$source" ;;
    ado_mcp_check|linear_mcp_check) add_result "$name" "unchecked" "Check via MCP" ;;
    *)                add_result "$name" "unchecked" "Unknown method: $method" ;;
  esac
done < "$CONF_FILE"

# --- Output ---

if $JSON_OUTPUT; then
  # JSON output
  echo "["
  first=true
  for entry in "${RESULTS[@]}"; do
    IFS='|' read -r name status details <<< "$entry"
    symbol=$(status_symbol "$status")

    # In quiet mode, skip valid/unchecked
    if $QUIET_MODE && [[ "$status" == "valid" || "$status" == "unchecked" ]]; then
      continue
    fi

    if ! $first; then echo ","; fi
    first=false

    # Escape quotes in details for JSON
    details="${details//\\/\\\\}"
    details="${details//\"/\\\"}"

    printf '  {"name": "%s", "status": "%s", "symbol": "%s", "details": "%s"}' \
      "$name" "$status" "$symbol" "$details"
  done
  echo ""
  echo "]"
else
  # Table output
  printf "\n%-28s %-10s %s\n" "Token Name" "Status" "Details"
  printf "%-28s %-10s %s\n" "----------------------------" "----------" "-------------------------------------------"

  for entry in "${RESULTS[@]}"; do
    IFS='|' read -r name status details <<< "$entry"
    symbol=$(status_symbol "$status")

    # In quiet mode, skip valid/unchecked
    if $QUIET_MODE && [[ "$status" == "valid" || "$status" == "unchecked" ]]; then
      continue
    fi

    printf "%-28s %-10s %s\n" "$name" "$symbol $status" "$details"
  done
  echo ""
fi

# --- Exit code ---

if $HAS_EXPIRED; then
  exit 1
elif $HAS_EXPIRING; then
  exit 2
else
  exit 0
fi
